"""会话归档：按「根目录 x 月份」把冷会话文件整体打包成 tar.zst.age，校验无误后才删原文件。

配置来自环境变量，由 nix 包装注入：
  SESSION_ARCHIVE_ROOTS     要扫描的根目录，换行分隔，不存在的目录跳过
  SESSION_ARCHIVE_DAYS      一个月结束后再过多少天才封存
  SESSION_ARCHIVE_KEY_FILE  age 私钥文件，可含多把；加密给其中全部公钥，解密用其中任一把

用法见 README.md。外部接缝只有 zstd 与 age 两个命令，e2e 用 PATH 垫片向它们注入失败。
"""

import argparse
import contextlib
import datetime as dt
import fcntl
import fnmatch
import json
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
from collections import Counter, defaultdict
from dataclasses import dataclass

CHUNK = 1 << 20
TAR_SUFFIX = ".tar.zst.age"
IDX_SUFFIX = ".idx.age"
VOLUME_RE = re.compile(
    r"^archive-(\d{4}-\d{2})(?:-(\d+))?" + re.escape(TAR_SUFFIX) + "$"
)
# 根目录直属文件由 plan 按深度整体排除，这里只列子目录里要跳过的名字
EXCLUDED_NAMES = (".DS_Store", "*.part", "*.lock*")
LOCK_NAME = ".session-archive.lock"


class Failure(Exception):
    """单个月份或单个文件的处理失败，不影响其余部分"""


# 一个月份、一个还原目标的处理失败都按这组异常记账，不影响其余部分
ERRORS = (Failure, OSError, tarfile.TarError, subprocess.SubprocessError)


@dataclass(frozen=True)
class Config:
    roots: list[str]
    days: int
    key_file: str


def load_config() -> Config:
    roots = [
        r
        for r in os.environ["SESSION_ARCHIVE_ROOTS"].splitlines()
        if r and os.path.isdir(r)
    ]
    return Config(
        roots,
        int(os.environ["SESSION_ARCHIVE_DAYS"]),
        os.environ["SESSION_ARCHIVE_KEY_FILE"],
    )


def mib(n: int) -> str:
    return f"{n // (1 << 20)} MiB"


def unlink_quiet(path: str) -> None:
    with contextlib.suppress(FileNotFoundError):
        os.unlink(path)


# ───────────── 编解码：zstd + age，唯一的外部接缝 ─────────────


def recipient_args(key_file: str) -> list[str]:
    out = subprocess.run(
        ["age-keygen", "-y", key_file], capture_output=True, text=True, check=True
    ).stdout
    recipients = out.split()
    if not recipients:
        raise Failure("密钥文件里没有公钥")
    return [arg for r in recipients for arg in ("-r", r)]


def encode(write_plain, out_path: str, recips: list[str]) -> None:
    """write_plain(fileobj) 写出的明文经 zstd 压缩、age 加密后落到 out_path"""
    zstd = subprocess.Popen(
        ["zstd", "-19", "--long=27", "-T0", "-q", "-c"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
    )
    age = subprocess.Popen(["age", *recips, "-o", out_path], stdin=zstd.stdout)
    zstd.stdout.close()
    try:
        try:
            write_plain(zstd.stdin)
            zstd.stdin.close()
        except BrokenPipeError:
            pass  # 下游提前退出，由返回码给出失败
    except BaseException:
        zstd.kill()
        age.kill()
        raise
    finally:
        with contextlib.suppress(OSError):
            zstd.stdin.close()
        zstd.wait()
        age.wait()
    if zstd.returncode or age.returncode:
        raise Failure("压缩或加密失败")


@contextlib.contextmanager
def decrypted(path: str, key_file: str):
    """age 解密后的字节流（仍是 zstd 压缩的）。不检查返回码，只供 rekey 比对两份密文的内容"""
    age = subprocess.Popen(["age", "-d", "-i", key_file, path], stdout=subprocess.PIPE)
    try:
        yield age.stdout
    finally:
        age.stdout.close()
        age.kill()
        age.wait()


@contextlib.contextmanager
def decoded(path: str, key_file: str):
    """解密并解压后的明文字节流。退出时读完整个流并检查返回码，不完整的流视为失败"""
    age = subprocess.Popen(["age", "-d", "-i", key_file, path], stdout=subprocess.PIPE)
    zstd = subprocess.Popen(
        ["zstd", "-d", "-q", "-c"], stdin=age.stdout, stdout=subprocess.PIPE
    )
    age.stdout.close()
    clean = False
    try:
        yield zstd.stdout
        while zstd.stdout.read(CHUNK):
            pass
        clean = True
    finally:
        zstd.stdout.close()
        if not clean:
            zstd.kill()
            age.kill()
        zstd.wait()
        age.wait()
    if zstd.returncode or age.returncode:
        raise Failure(f"解密或解压失败: {path}")


def read_exact(f, n: int) -> bytes:
    parts = []
    while n > 0:
        b = f.read(n)
        if not b:
            break
        parts.append(b)
        n -= len(b)
    return b"".join(parts)


def same_stream(a, b) -> bool:
    while True:
        x, y = read_exact(a, CHUNK), read_exact(b, CHUNK)
        if x != y:
            return False
        if not x:
            return True


# ───────────── 规划：哪些月份封存，哪些文件进哪个月 ─────────────


def month_of(mtime: float) -> str:
    return dt.datetime.fromtimestamp(mtime).strftime("%Y-%m")


def seal_time(month: str, days: int) -> dt.datetime:
    """月份结束后再过 days 天，该月所有文件都已是冷文件"""
    y, m = map(int, month.split("-"))
    end = dt.datetime(y + (m == 12), m % 12 + 1, 1)
    return end + dt.timedelta(days=days)


def plan(root: str, now: float, days: int):
    """返回 (已封存月份 -> [(相对路径, 大小)], 等待中月份 -> [...], 不可读文件)"""
    by_month: dict[str, list[tuple[str, int]]] = defaultdict(list)
    unreadable: list[str] = []
    for d, _, files in os.walk(root):
        if d == root:
            continue  # 根目录直属文件是 agent 自己的状态（如 sqlite 库），不碰
        for name in files:
            if any(fnmatch.fnmatchcase(name, pat) for pat in EXCLUDED_NAMES):
                continue
            path = os.path.join(d, name)
            rel = os.path.relpath(path, root)
            try:
                st = os.lstat(path)
            except OSError:  # 目录无进入权限，或枚举后文件被删
                unreadable.append(rel)
                continue
            if not stat.S_ISREG(st.st_mode):
                continue
            if not os.access(path, os.R_OK):
                unreadable.append(rel)
                continue
            by_month[month_of(st.st_mtime)].append((rel, st.st_size))
    now_dt = dt.datetime.fromtimestamp(now)
    sealed = {m: sorted(v) for m, v in by_month.items() if seal_time(m, days) <= now_dt}
    waiting = {m: sorted(v) for m, v in by_month.items() if m not in sealed}
    return sealed, waiting, unreadable


# ───────────── 归档卷：archive-<月份>[-<序号>].tar.zst.age + .idx.age ─────────────


@dataclass(frozen=True)
class Volume:
    month: str
    number: int
    root: str

    @property
    def base(self) -> str:
        return f"archive-{self.month}" + ("" if self.number == 1 else f"-{self.number}")

    @property
    def tar(self) -> str:
        return os.path.join(self.root, self.base + TAR_SUFFIX)

    @property
    def idx(self) -> str:
        return os.path.join(self.root, self.base + IDX_SUFFIX)


def volumes(root: str, month: str | None = None) -> list[Volume]:
    found = []
    for name in os.listdir(root):
        m = VOLUME_RE.match(name)
        if m and (month is None or m.group(1) == month):
            found.append(Volume(m.group(1), int(m.group(2) or 1), root))
    return sorted(found, key=lambda v: (v.month, v.number))


def read_index(vol: Volume, key_file: str) -> list[tuple[str, int]]:
    with decoded(vol.idx, key_file) as s:
        return [(rel, size) for rel, size in json.loads(s.read())]


def write_tar(out, root: str, members: list[str]) -> None:
    with tarfile.open(fileobj=out, mode="w|", format=tarfile.GNU_FORMAT) as tf:
        for rel in members:
            path = os.path.join(root, rel)
            info = tf.gettarinfo(path, arcname=rel)
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            with open(path, "rb") as f:
                tf.addfile(info, f)


def verify(tar_path: str, root: str, members: list[str], key_file: str) -> None:
    """归档里每个成员必须与磁盘上的原文件逐字节一致，members 必须全部出现"""
    want, seen = set(members), set()
    with decoded(tar_path, key_file) as s, tarfile.open(fileobj=s, mode="r|") as tf:
        for info in tf:
            if info.name not in want:
                continue
            with (
                tf.extractfile(info) as a,
                open(os.path.join(root, info.name), "rb") as b,
            ):
                if not same_stream(a, b):
                    raise Failure(f"内容与原文件不一致: {info.name}")
            seen.add(info.name)
    if seen != want:
        raise Failure(f"归档缺少 {len(want - seen)} 个文件，例如 {min(want - seen)}")


def seal(
    root: str,
    month: str,
    members: list[tuple[str, int]],
    key_file: str,
    recips: list[str],
) -> Volume:
    existing = volumes(root, month)
    vol = Volume(month, existing[-1].number + 1 if existing else 1, root)
    rels = [rel for rel, _ in members]
    tar_part, idx_part = vol.tar + ".part", vol.idx + ".part"
    try:
        encode(lambda out: write_tar(out, root, rels), tar_part, recips)
        verify(tar_part, root, rels, key_file)
        encode(lambda out: out.write(json.dumps(members).encode()), idx_part, recips)
        # 清单先落地：只有 tar 存在才算分卷，没有 tar 的清单是崩溃残留，下次会被覆盖
        os.replace(idx_part, vol.idx)
        os.replace(tar_part, vol.tar)
    finally:
        unlink_quiet(tar_part)
        unlink_quiet(idx_part)
    return vol


@contextlib.contextmanager
def root_lock(root: str):
    """同一根目录同时只允许一个归档进程：卷名和 .part 名都由根目录内状态决定"""
    try:
        fd = os.open(os.path.join(root, LOCK_NAME), os.O_RDWR | os.O_CREAT, 0o600)
    except OSError as e:
        raise Failure(f"无法创建锁文件 {root}: {e}") from None
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise Failure(f"已有另一个 session-archive 在处理 {root}") from None
        yield
    finally:
        os.close(fd)


def signature(path: str) -> tuple[int, int, int]:
    st = os.lstat(path)
    return st.st_ino, st.st_size, st.st_mtime_ns


def delete_originals(root: str, snap: dict[str, tuple[int, int, int]]) -> None:
    """只删仍与打包前快照一致的文件；打包后被写过的保留，之后按迟到文件处理"""
    for rel, sig in sorted(snap.items()):
        try:
            if signature(os.path.join(root, rel)) != sig:
                print(f"打包后文件有变化，保留: {rel}", file=sys.stderr)
                continue
        except FileNotFoundError:
            continue
        os.unlink(os.path.join(root, rel))
        parent = os.path.dirname(os.path.join(root, rel))
        while parent != root:
            try:
                os.rmdir(parent)  # 只删因此变空的目录
            except OSError:
                break
            parent = os.path.dirname(parent)


def archive_month(
    root: str,
    month: str,
    members: list[tuple[str, int]],
    cfg: Config,
    recips: list[str],
) -> list[Volume]:
    """返回本次新写的分卷。已有分卷已覆盖且内容一致的文件只补删原文件"""
    pending = dict(members)
    snap = {rel: signature(os.path.join(root, rel)) for rel in pending}
    for vol in volumes(root, month):
        try:
            indexed = {rel for rel, _ in read_index(vol, cfg.key_file)}
        except (Failure, OSError, ValueError):
            continue
        covered = sorted(r for r in pending if r in indexed)
        if not covered:
            continue
        try:
            verify(vol.tar, root, covered, cfg.key_file)
        except (Failure, OSError, tarfile.TarError):
            continue  # 同名但内容不同，留给新分卷
        delete_originals(root, {r: snap[r] for r in covered})
        for r in covered:
            del pending[r]
    if not pending:
        return []
    vol = seal(root, month, sorted(pending.items()), cfg.key_file, recips)
    delete_originals(root, {r: snap[r] for r in pending})
    return [vol]


# ───────────── 命令 ─────────────


def print_exts(rels: list[str]) -> None:
    if not rels:
        return
    counts = Counter(os.path.splitext(r)[1] or "(无后缀)" for r in rels)
    print("后缀统计 top 10:")
    for ext, n in counts.most_common(10):
        print(f"  {n:6d} {ext}")


def run_root(
    cfg: Config, root: str, now: float, dry: bool, recips: list[str], archived: list
) -> int:
    """处理一个根目录，返回失败数；已归档的相对路径追加到 archived"""
    sealed, waiting, unreadable = plan(root, now, cfg.days)
    for rel in unreadable:
        print(f"无法读取，跳过: {os.path.join(root, rel)}", file=sys.stderr)
    failed = len(unreadable)
    for month, members in sorted(sealed.items()):
        total = sum(s for _, s in members)
        if dry:
            print(f"{root} {month}: {len(members)} 个文件, {mib(total)}，将封存")
            archived += [r for r, _ in members]
            continue
        print(f"封存 {root} {month}: {len(members)} 个文件, {mib(total)}")
        try:
            new = archive_month(root, month, members, cfg, recips)
        except ERRORS as e:
            print(f"失败，原文件保留: {root} {month}: {e}", file=sys.stderr)
            failed += 1
            continue
        archived += [r for r, _ in members]
        for vol in new:
            size = os.path.getsize(vol.tar) + os.path.getsize(vol.idx)
            print(f"  -> {os.path.basename(vol.tar)}: {mib(total)} -> {mib(size)}")
    if dry:
        for month, members in sorted(waiting.items()):
            print(
                f"{root} {month}: {len(members)} 个文件, {mib(sum(s for _, s in members))}，{seal_time(month, cfg.days):%Y-%m-%d} 起可封存"
            )
    return failed


def cmd_run(cfg: Config, dry: bool) -> int:
    recips = [] if dry else recipient_args(cfg.key_file)
    now, archived, failed = time.time(), [], 0
    for root in cfg.roots:
        try:
            # dry-run 不写不删，不需要锁
            with contextlib.nullcontext() if dry else root_lock(root):
                failed += run_root(cfg, root, now, dry, recips, archived)
        except Failure as e:
            print(f"跳过: {e}", file=sys.stderr)
            failed += 1
    print_exts(archived)
    print(f"{'dry-run: 不写不删' if dry else '完成'}，失败 {failed} 个")
    return 1 if failed else 0


def restore(vol: Volume, key_file: str) -> None:
    """还原整卷到它所在的根目录。已存在的文件不覆盖；还原出的是新文件，mtime 为现在"""
    with decoded(vol.tar, key_file) as s, tarfile.open(fileobj=s, mode="r|") as tf:
        for info in tf:
            if not info.isreg():
                continue
            # data_filter 拒绝会落到根目录外的成员路径，包括经已有符号链接绕出去的
            dest = os.path.join(vol.root, tarfile.data_filter(info, vol.root).name)
            if os.path.lexists(dest):
                print(f"目标已存在，跳过: {dest}", file=sys.stderr)
                continue
            parent = os.path.dirname(dest)
            os.makedirs(parent, exist_ok=True)
            # 明文先写进唯一临时文件再 link：中断不留半截文件，link 不覆盖期间新建的同名文件
            with tempfile.NamedTemporaryFile(dir=parent, suffix=".part") as tmp:
                shutil.copyfileobj(tf.extractfile(info), tmp, CHUNK)
                tmp.flush()
                try:
                    os.link(tmp.name, dest)
                    print(f"已还原: {dest}")
                except FileExistsError:
                    print(f"目标已存在，跳过: {dest}", file=sys.stderr)


def parse_volume(path: str) -> Volume:
    m = VOLUME_RE.match(os.path.basename(path))
    if not (m and os.path.isfile(path)):
        raise Failure(f"不是归档卷: {path}")
    return Volume(
        m.group(1), int(m.group(2) or 1), os.path.dirname(os.path.abspath(path))
    )


def cmd_restore(cfg: Config, targets: list[str]) -> int:
    failed = 0
    for target in targets:
        try:
            restore(parse_volume(target), cfg.key_file)
        except ERRORS as e:
            print(f"还原失败: {target}: {e}", file=sys.stderr)
            failed += 1
    return 1 if failed else 0


def cmd_list(cfg: Config) -> int:
    try:
        for root in cfg.roots:
            for vol in volumes(root):
                index = read_index(vol, cfg.key_file)
                print(
                    f"{vol.tar}  {len(index)} 个文件, {mib(sum(s for _, s in index))} -> {mib(os.path.getsize(vol.tar))}"
                )
    except ERRORS as e:
        print(f"失败: {e}", file=sys.stderr)
        return 1
    return 0


def rekey_file(path: str, key_file: str, recips: list[str]) -> None:
    """解密再用当前全部公钥加密，不动压缩层；比对两边解密结果一致才替换"""
    part, st = path + ".part", os.stat(path)
    dec = subprocess.Popen(["age", "-d", "-i", key_file, path], stdout=subprocess.PIPE)
    enc = subprocess.Popen(["age", *recips, "-o", part], stdin=dec.stdout)
    dec.stdout.close()
    try:
        try:
            dec.wait()
            enc.wait()
        except BaseException:
            dec.kill()
            enc.kill()
            raise
        if dec.returncode or enc.returncode:
            raise Failure("解密或重新加密失败")
        with decrypted(path, key_file) as a, decrypted(part, key_file) as b:
            if not same_stream(a, b):
                raise Failure("重新加密后内容不一致")
        os.utime(part, ns=(st.st_atime_ns, st.st_mtime_ns))
        os.replace(part, path)
    finally:
        unlink_quiet(part)


def cmd_rekey(cfg: Config) -> int:
    recips, n, failed = recipient_args(cfg.key_file), 0, 0
    for root in cfg.roots:
        try:
            with root_lock(root):
                for vol in volumes(root):
                    for path in (vol.tar, vol.idx):
                        if not os.path.exists(path):
                            continue
                        try:
                            rekey_file(path, cfg.key_file, recips)
                            n += 1
                        except (Failure, OSError, subprocess.SubprocessError) as e:
                            print(f"换钥失败: {path}: {e}", file=sys.stderr)
                            failed += 1
        except Failure as e:
            print(f"跳过: {e}", file=sys.stderr)
            failed += 1
    print(f"完成: 换钥 {n} 个，失败 {failed} 个")
    return 1 if failed else 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(
        prog="session-archive", description="按月整体归档冷会话文件"
    )
    sub = ap.add_subparsers(dest="cmd", required=True)
    run = sub.add_parser("run", help="封存已满足条件的月份")
    run.add_argument(
        "--dry-run", action="store_true", help="只列出将封存与等待中的月份，不写不删"
    )
    sub.add_parser("list", help="列出全部归档卷")
    sub.add_parser(
        "restore", help="把归档卷整卷还原到它所在的根目录，已存在的文件不覆盖"
    ).add_argument("targets", nargs="+", metavar="归档卷")
    sub.add_parser("rekey", help="用密钥文件里的当前全部公钥重新加密全部归档卷")
    args = ap.parse_args(argv)

    os.umask(0o077)
    # 被终止时走 finally 清掉 .part，restore 的 .part 是明文
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    cfg = load_config()
    if args.cmd == "run":
        return cmd_run(cfg, args.dry_run)
    if args.cmd == "list":
        return cmd_list(cfg)
    if args.cmd == "restore":
        return cmd_restore(cfg, args.targets)
    return cmd_rekey(cfg)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
