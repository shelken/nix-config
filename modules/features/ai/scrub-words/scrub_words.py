#!/usr/bin/env python3
"""按本地脏话字典批量替换 omp / pi 会话 jsonl，并保留可撤销的原文日志。

字典：每行 `词 -> 替换词`（替换词留空即删除该词），# 开头为注释，不进任何仓库。
命令：dry-run | run | undo [RUNID] | purge [RUNID | --all]
"""

import argparse
import fcntl
import gzip
import hashlib
import json
import mmap
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

HOME = Path.home()
DEFAULT_DICT = HOME / ".config/scrub-words/dict.txt"
DEFAULT_CACHE = HOME / ".cache/scrub-words"
DEFAULT_ROOTS = [HOME / ".omp/agent/sessions", HOME / ".pi/agent/sessions"]
JOURNAL = "journal.jsonl.gz"
LIST_LIMIT = 10

# 这些字段携带 provider 对 thinking/工具调用内容的签名或加密态，改正文会让续聊校验失败。
# reasoning_content 与 {"v":1,...}（仅消息 ID）不是内容签名。
SIGNATURE_KEYS = {"thinkingSignature", "thoughtSignature", "encrypted_content", "textSignature"}
NO_SIGNATURE = {"", "reasoning_content"}

# JSON 文本里的 \n \t \uXXXX 紧贴英文词时，词前其实是边界，不能按字母数字挡掉。
BEFORE = r"(?:(?<![A-Za-z0-9_])|(?<=\\[ntrbf])|(?<=\\u[0-9a-fA-F]{4}))"
AFTER = r"(?![A-Za-z0-9_])"
UNSAFE = re.compile(r'["\\\x00-\x1f]')  # 会破坏 JSON 文本的字符
TITLE_PAD = re.compile(rb'"pad":"( *)"\}$')  # omp 首行定长 title，靠 pad 补齐


class Changed(Exception):
    """文件在扫描后被别的进程改过。"""


# ---------------------------------------------------------------- 字典与匹配


def load_dict(path):
    if not path.is_file():
        sys.exit(f"字典不存在：{path}\n每行写 `词 -> 替换词`（替换词留空即删除），# 开头为注释")
    entries, errors = {}, []
    for n, raw in enumerate(path.read_text(encoding="utf-8").split("\n"), 1):
        raw = raw.strip()
        if not raw or raw.startswith("#"):
            continue
        key, sep, val = (s.strip() for s in raw.partition("->"))
        if not sep or not key:
            errors.append(f"第 {n} 行：需要 `词 -> 替换词`")
        elif UNSAFE.search(key) or UNSAFE.search(val):
            errors.append(f"第 {n} 行：不得含双引号、反斜杠或控制字符")
        elif key in entries:
            errors.append(f"第 {n} 行：重复的词 {key!r}")
        else:
            entries[key] = val
    if not entries and not errors:
        errors.append("字典为空")
    if errors:
        sys.exit(f"字典 {path} 有误：\n  " + "\n  ".join(errors))
    return entries


class Matcher:
    """单次扫描、长词优先；非 ASCII 词额外匹配 \\uXXXX 转义形式。"""

    def __init__(self, entries):
        alts = []  # (匹配文本长度, 正则, 词, 替换后的字节, 匹配文本)
        for key, val in entries.items():
            variants = [(key, val)]
            esc_key, esc_val = json.dumps(key)[1:-1], json.dumps(val)[1:-1]
            if esc_key != key:
                variants.append((esc_key, esc_val))
            for k, v in variants:
                body = re.escape(k)
                pat = f"{BEFORE}(?i:{body}){AFTER}" if key.isascii() else body
                alts.append((len(k), pat, key, v.encode(), k))
        alts.sort(key=lambda a: -a[0])
        self.labels = {f"g{i}": a[2] for i, a in enumerate(alts)}
        self.values = {f"g{i}": a[3] for i, a in enumerate(alts)}
        self.escaped = {f"g{i}": a[4] != a[2] for i, a in enumerate(alts)}  # 是否 \uXXXX 转义形式
        self.rx = re.compile("|".join(f"(?P<g{i}>{a[1]})" for i, a in enumerate(alts)).encode())
        # 预筛：字面量查找比正则快约 20 倍，先排除绝大多数不含词的文件和行
        self.needles = [a[4].encode() for a in alts if not a[2].isascii()]
        ascii_pats = [a[1] for a in alts if a[2].isascii()]
        self.ascii_rx = re.compile("|".join(ascii_pats).encode()) if ascii_pats else None
        self.mapping = dict(entries)
        for key, val in entries.items():
            if self.rx.search(val.encode()):
                sys.exit(f"字典有误：{key!r} 的替换词 {val!r} 含有字典里的词，多次运行会连锁替换")

    def maybe(self, data):
        """可能含词（不保证）；data 可以是 bytes 或 mmap。"""
        return any(data.find(n) != -1 for n in self.needles) or bool(
            self.ascii_rx and self.ascii_rx.search(data)
        )


# ---------------------------------------------------------------- 扫描与计划


@dataclass
class Change:
    idx: int  # 0 起的行下标
    old: bytes
    new: bytes


@dataclass
class Plan:
    path: Path
    key: tuple  # (mtime_ns, size)，写回前用来确认文件没被改
    changes: list = field(default_factory=list)
    counts: Counter = field(default_factory=Counter)
    samples: dict = field(default_factory=dict)
    protected: list = field(default_factory=list)  # (行号, 原因)


def iter_jsonl(roots):
    for root in roots:
        for d, dirs, files in os.walk(root):
            dirs.sort()
            for f in sorted(files):
                p = Path(d) / f
                if f.endswith(".jsonl") and not p.is_symlink():
                    yield p


def has_signature(obj):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in SIGNATURE_KEYS and isinstance(v, str):
                if v not in NO_SIGNATURE and not v.startswith('{"v":1,'):
                    return True
            elif has_signature(v):
                return True
    elif isinstance(obj, list):
        return any(has_signature(x) for x in obj)
    return False


def escaped_backslash(line, pos):
    """pos 前的反斜杠个数为奇数，说明 pos 处的反斜杠只是被转义的字面量，不是 JSON 转义的开头。"""
    n = 0
    while pos - n > 0 and line[pos - n - 1] == 0x5C:
        n += 1
    return n % 2 == 1


def keep_title_length(old, new):
    m = TITLE_PAD.search(new)
    pad = len(m.group(1)) - (len(new) - len(old)) if m else -1
    if pad < 0:
        return None
    return new[: m.start(1)] + b" " * pad + new[m.end(1) :]


def plan_file(path, m):
    with open(path, "rb") as f:
        st = os.fstat(f.fileno())
        data = f.read()
    if not m.maybe(data):
        return None
    plan = Plan(path, (st.st_mtime_ns, st.st_size))
    for idx, line in enumerate(data.split(b"\n")):
        if not m.maybe(line):
            continue
        hits = []

        def repl(mo):
            if m.escaped[mo.lastgroup] and escaped_backslash(line, mo.start()):
                return mo.group()
            hits.append((m.labels[mo.lastgroup], line[max(0, mo.start() - 20) : mo.end() + 20]))
            return m.values[mo.lastgroup]

        new = m.rx.sub(repl, line)
        if not hits:
            continue
        try:
            if has_signature(json.loads(line)):
                plan.protected.append((idx + 1, "带 provider 签名"))
                continue
        except ValueError:
            plan.protected.append((idx + 1, "JSON 无法解析"))
            continue
        if idx == 0 and line.startswith(b'{"type":"title"'):
            new = keep_title_length(line, new)
            if new is None:
                plan.protected.append((1, "title 行 pad 不够补齐长度"))
                continue
        plan.changes.append(Change(idx, line, new))
        for label, ctx in hits:
            plan.counts[label] += 1
            samples = plan.samples.setdefault(label, [])
            if len(samples) < 3:
                samples.append(ctx.decode("utf-8", "ignore"))
    return plan


def open_paths(paths):
    """一次 lsof 找出其中正被进程打开的文件。"""
    if not paths:
        return set()
    try:
        out = subprocess.run(
            ["lsof", "-w", "-F", "n", "--", *map(str, paths)], capture_output=True, text=True
        ).stdout
    except FileNotFoundError:
        sys.exit("找不到 lsof，无法确认文件是否被占用")
    return {os.path.realpath(line[1:]) for line in out.split("\n") if line.startswith("n")}


def split_active(plans, min_age):
    """跳过近期写入或被进程打开的文件，避免 rename 后活跃进程的追加写进旧 inode。"""
    now = time.time()
    stale = lambda p: now - p.key[0] / 1e9 >= min_age * 60
    busy = open_paths([p.path for p in plans if stale(p)])
    ok, skipped = [], []
    for p in plans:
        if not stale(p):
            skipped.append((p, f"{min_age:g} 分钟内有写入"))
        elif os.path.realpath(p.path) in busy:
            skipped.append((p, "被进程打开"))
        else:
            ok.append(p)
    return ok, skipped


_last_progress = 0.0


def progress(label, i, total):
    """全量扫描要一两分钟，没有输出会像卡死；只在终端里刷新，管道和测试里保持安静。"""
    global _last_progress
    now = time.monotonic()
    if sys.stderr.isatty() and total and (i == total or now - _last_progress >= 0.3):
        _last_progress = now
        sys.stderr.write(f"\r{label} {i}/{total}" + ("\n" if i == total else ""))
        sys.stderr.flush()


def collect(args, m):
    files = list(iter_jsonl(args.root))
    plans = []
    for i, path in enumerate(files, 1):
        progress("扫描会话", i, len(files))
        plan = plan_file(path, m)
        if plan and (plan.changes or plan.protected):
            plans.append(plan)
    ok, skipped = split_active(plans, args.min_age)
    per_root = Counter(next(r for r in args.root if r in p.parents) for p in files)
    return per_root, ok, skipped


# ---------------------------------------------------------------- 写回


def apply_edits(path, key, changes):
    """写临时文件再 rename，保留权限与 mtime；失败不留半成品。"""
    with open(path, "rb") as f:
        st = os.fstat(f.fileno())
        data = f.read()
    if (st.st_mtime_ns, st.st_size) != key:
        raise Changed("文件已被修改")
    lines = data.split(b"\n")
    for c in changes:
        if c.idx >= len(lines) or lines[c.idx] != c.old:
            raise Changed("行内容已变化")
        lines[c.idx] = c.new
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".scrub-tmp")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(b"\n".join(lines))
            f.flush()
            os.fsync(f.fileno())
        shutil.copymode(path, tmp)
        os.utime(tmp, ns=(st.st_atime_ns, st.st_mtime_ns))  # 保持会话列表的排序
        now = path.stat()
        if (now.st_mtime_ns, now.st_size) != key:
            raise Changed("写入期间文件被修改")
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


# ---------------------------------------------------------------- 输出


def fmt_size(n):
    return f"{n / 1024 / 1024:.1f} MB" if n >= 1024 * 1024 else f"{n / 1024:.1f} KB"


def dir_size(path):
    return sum(f.stat().st_size for f in Path(path).rglob("*") if f.is_file())


def show_list(items):
    for item in items[:LIST_LIMIT]:
        print(f"    {item}")
    if len(items) > LIST_LIMIT:
        print(f"    …另 {len(items) - LIST_LIMIT} 项")


def root_summary(roots, per_root, plans, verb):
    """分目录汇总，避免只看到文件清单前 10 项时误以为只处理了其中一个目录。"""
    for r in roots:
        mine = [p for p in plans if r in p.path.parents]
        changed = sum(len(p.changes) for p in mine)
        kept = sum(len(p.protected) for p in mine)
        files = sum(1 for p in mine if p.changes)
        print(f"  {r}：扫描 {per_root[r]} 个 / {verb} {changed} 行（{files} 个文件） / 未替换 {kept} 行")


def report(plans, skipped, m, verb, samples, lists=True):
    counts, files = Counter(), Counter()
    ctxs = {}
    for p in plans:
        for label, n in p.counts.items():
            counts[label] += n
            files[label] += 1
            ctxs.setdefault(label, []).extend(p.samples[label])
    print(f"\n{verb}：")
    if not counts:
        print("  无")
    for label, n in counts.most_common():
        print(f"  {label} → {m.mapping[label]}  {n} 处 / {files[label]} 个文件")
        if samples:
            for ctx in ctxs[label][:3]:
                print(f"      …{ctx}…")
    protected = [f"{p.path}:{ln}  {why}" for p in plans for ln, why in p.protected]
    if protected:
        print(f"\n未替换（{len(protected)} 行）" + ("：" if lists else ""))
        if lists:
            show_list(protected)
    if skipped:
        print(f"\n跳过的文件（{len(skipped)} 个，下次再处理）" + ("：" if lists else ""))
        if lists:
            show_list([f"{p.path}  {why}" for p, why in skipped])


def audit(args, m):
    """列出 agent 目录里、不在清洗范围内的残留命中。"""
    candidates = []
    for parent in sorted({r.parent for r in args.root}):
        for d, _, files in os.walk(parent):
            for f in files:
                p = Path(d) / f
                if p == args.dict or args.cache in p.parents:
                    continue
                if f.endswith(".jsonl") and any(r in p.parents for r in args.root):
                    continue
                candidates.append(p)
    found = []
    for i, p in enumerate(candidates, 1):
        progress("审计范围外", i, len(candidates))
        try:
            if not stat.S_ISREG(os.lstat(p).st_mode):  # 软链接、FIFO 等：打开 FIFO 会永久阻塞
                continue
            with open(p, "rb") as fh, mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_READ) as mm:
                if m.maybe(mm) and m.rx.search(mm):
                    found.append(p)
        except (OSError, ValueError):  # 空文件或不可读
            pass
    print(f"\n范围外仍有命中（{len(found)} 个文件，不自动改）：")
    if not found:
        print("  无")
        return
    for suffix, n in Counter(p.suffix or "(无后缀)" for p in found).most_common():
        print(f"  {suffix}: {n}")
    if not args.stat:
        show_list([str(p) for p in found if p.suffix != ".log"])


# ---------------------------------------------------------------- 撤销日志


def list_runs(cache):
    runs = []
    for d in sorted(cache.glob(f"*/{JOURNAL}")):
        records = read_journal(d.parent)
        runs.append((d.parent, len(records), len({r["file"] for r in records})))
    return runs


def read_journal(run_dir):
    records = []
    try:
        with gzip.open(run_dir / JOURNAL, "rt", encoding="utf-8") as f:
            for line in f:
                records.append(json.loads(line))
    except EOFError:  # 运行中途中断，保留已写入的部分
        pass
    return records


def cache_total(cache):
    return fmt_size(dir_size(cache)) if cache.exists() else "0 KB"


# ---------------------------------------------------------------- 命令


def cmd_dry_run(args):
    m = Matcher(load_dict(args.dict))
    scanned, ok, skipped = collect(args, m)
    print(f"字典 {len(m.mapping)} 项；扫描 {sum(scanned.values())} 个 jsonl")
    root_summary(args.root, scanned, ok, "将替换")
    report(ok, skipped, m, "将替换", samples=not args.stat, lists=not args.stat)
    if not args.no_audit:
        audit(args, m)


def cmd_run(args):
    m = Matcher(load_dict(args.dict))
    scanned, ok, skipped = collect(args, m)
    runid = time.strftime("%Y%m%dT%H%M%S")
    done, journal = [], None
    try:
        for p in filter(lambda p: p.changes, ok):
            if journal is None:
                (args.cache / runid).mkdir(parents=True)
                journal = gzip.open(args.cache / runid / JOURNAL, "wt", encoding="utf-8")
            # 先落日志再改文件：中途崩溃也不会丢原文
            for c in p.changes:
                rec = {
                    "file": str(p.path),
                    "line": c.idx + 1,
                    "old": c.old.decode("utf-8", "surrogateescape"),
                    "new_sha": hashlib.sha256(c.new).hexdigest(),
                }
                journal.write(json.dumps(rec) + "\n")
            journal.flush()
            os.fsync(journal.fileno())
            try:
                apply_edits(p.path, p.key, p.changes)
                done.append(p)
            except (Changed, OSError) as e:
                skipped.append((p, str(e)))
    finally:
        if journal:
            journal.close()
    print(f"扫描 {sum(scanned.values())} 个 jsonl")
    shown = done + [p for p in ok if not p.changes]  # 只含受保护行的文件也要计入"未替换"
    root_summary(args.root, scanned, shown, "已替换")
    report(shown, skipped, m, "已替换", samples=False, lists=not args.stat)
    if done:
        lines = sum(len(p.changes) for p in done)
        print(f"\nrunid={runid}：{len(done)} 个文件 / {lines} 行；撤销：scrub-words undo {runid}")
    print(f"撤销日志当前共占 {cache_total(args.cache)}（scrub-words purge 清理）")


def pick_run(args):
    runs = list_runs(args.cache)
    if args.runid:
        runs = [r for r in runs if r[0].name == args.runid]
    if not runs:
        sys.exit("没有可用的撤销日志")
    return runs[-1][0]


def cmd_undo(args):
    run_dir = pick_run(args)
    groups = {}
    for rec in read_journal(run_dir):
        groups.setdefault(rec["file"], []).append(rec)
    plans, problems, already = [], [], 0
    for file, recs in groups.items():
        path = Path(file)
        try:
            with open(path, "rb") as f:
                st = os.fstat(f.fileno())
                lines = f.read().split(b"\n")
        except FileNotFoundError:
            problems.append(f"{path}  文件不存在")
            continue
        plan = Plan(path, (st.st_mtime_ns, st.st_size))
        for rec in recs:
            idx, old = rec["line"] - 1, rec["old"].encode("utf-8", "surrogateescape")
            cur = lines[idx] if idx < len(lines) else None
            if cur == old:
                already += 1
            elif cur is not None and hashlib.sha256(cur).hexdigest() == rec["new_sha"]:
                plan.changes.append(Change(idx, cur, old))
            else:
                problems.append(f"{path}:{rec['line']}  内容已被改动，不恢复")
        if plan.changes:
            plans.append(plan)
    ok, skipped = split_active(plans, args.min_age)
    restored = 0
    for p in ok:
        try:
            apply_edits(p.path, p.key, p.changes)
            restored += len(p.changes)
        except (Changed, OSError) as e:
            skipped.append((p, str(e)))
    print(f"run {run_dir.name}：恢复 {restored} 行，已是原文 {already} 行")
    if problems:
        print(f"\n未恢复（{len(problems)} 行）：")
        show_list(problems)
    if skipped:
        print(f"\n跳过的文件（{len(skipped)} 个，稍后重试）：")
        show_list([f"{p.path}  {why}" for p, why in skipped])
    if not problems and not skipped:
        shutil.rmtree(run_dir)
        print("已全部恢复，撤销日志已删除")


def cmd_purge(args):
    runs = list_runs(args.cache)
    if not runs:
        sys.exit("没有撤销日志")
    for i, (d, lines, files) in enumerate(runs, 1):
        when = time.strftime("%Y-%m-%d %H:%M", time.strptime(d.name, "%Y%m%dT%H%M%S"))
        print(f"  {i}. {d.name}  {when}  {files} 个文件 / {lines} 行  {fmt_size(dir_size(d))}")
    if args.all:
        chosen = runs
    elif args.runid:
        chosen = [r for r in runs if r[0].name == args.runid]
        if not chosen:
            sys.exit(f"找不到 {args.runid}")
    else:
        ans = input("删除哪些？编号用逗号分隔，all=全部，回车取消：").strip()
        if ans == "all":
            chosen = runs
        else:
            try:
                nums = [int(x) for x in ans.split(",") if x.strip()]
            except ValueError:
                nums = [0]
            if not all(1 <= n <= len(runs) for n in nums):
                sys.exit("编号无效")
            chosen = [runs[n - 1] for n in dict.fromkeys(nums)]
    for d, _, _ in chosen:
        shutil.rmtree(d)
    if args.cache.exists() and not any(args.cache.iterdir()):
        args.cache.rmdir()
    print(f"已删除 {len(chosen)} 个；撤销日志当前共占 {cache_total(args.cache)}")


def lock_cache(cache):
    """run / undo / purge 共用一把锁，避免 undo 在 run 仍写日志时把日志目录删掉。"""
    cache.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(f"{cache}.lock", os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        sys.exit("另一个 scrub-words 正在执行 run/undo/purge")
    # fd 保持打开，进程退出时自动释放


def main():
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--dict", type=Path, default=DEFAULT_DICT, help="字典路径")
    common.add_argument("--cache", type=Path, default=DEFAULT_CACHE, help="撤销日志目录")
    common.add_argument("--root", type=Path, action="append", help="会话根目录，可重复")
    common.add_argument("--min-age", type=float, default=30, help="跳过最近 N 分钟有写入的文件")
    parser = argparse.ArgumentParser(
        prog="scrub-words", description=__doc__, formatter_class=argparse.RawTextHelpFormatter
    )
    sub = parser.add_subparsers(dest="cmd", required=True)
    scan = argparse.ArgumentParser(add_help=False, parents=[common])
    scan.add_argument("--stat", action="store_true", help="只输出统计，不列出文件路径和上下文")
    dry = sub.add_parser("dry-run", parents=[scan], help="只统计命中与误伤，不改文件")
    dry.add_argument("--no-audit", action="store_true", help="不扫描清洗范围外的残留（可省约一分钟）")
    dry.set_defaults(fn=cmd_dry_run)
    sub.add_parser("run", parents=[scan], help="执行替换并记录撤销日志").set_defaults(fn=cmd_run)
    undo = sub.add_parser("undo", parents=[common], help="恢复某次 run（默认最近一次）")
    undo.add_argument("runid", nargs="?")
    undo.set_defaults(fn=cmd_undo)
    purge = sub.add_parser("purge", parents=[common], help="列出并删除撤销日志")
    purge.add_argument("runid", nargs="?")
    purge.add_argument("--all", action="store_true")
    purge.set_defaults(fn=cmd_purge)
    args = parser.parse_args()
    # 日志里记录绝对路径，换目录执行 undo 也不会动错文件
    args.dict, args.cache = args.dict.resolve(), args.cache.resolve()
    args.root = [r.resolve() for r in (args.root or DEFAULT_ROOTS) if r.is_dir()]
    if args.fn in (cmd_run, cmd_undo, cmd_purge):
        lock_cache(args.cache)
    try:
        args.fn(args)
    except KeyboardInterrupt:
        sys.exit("\n已中断；run 中途中断时，已替换的文件可用 scrub-words undo 撤销")


if __name__ == "__main__":
    main()
