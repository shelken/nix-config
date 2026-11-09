"""session_archive.py 端到端验证：临时目录 + 临时 age 密钥 + 改过 mtime 的假会话，不碰真实数据。

需要 age、age-keygen、zstd 在 PATH。用法: python3 e2e.py
失败路径用 PATH 垫片替换 zstd 注入，这是脚本唯一的外部接缝。
"""

import datetime as dt
import os
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "session_archive.py")
SECRET = f"SECRET-MARKER-{os.getpid()}"
NOW = time.time()
DAY = 86400


def month(days_ago: float) -> str:
    return dt.datetime.fromtimestamp(NOW - days_ago * DAY).strftime("%Y-%m")


def ok(msg: str) -> None:
    print("ok:", msg, flush=True)


def check(cond: bool, msg: str) -> None:
    if not cond:
        print("FAIL:", msg, file=sys.stderr)
        sys.exit(1)


work = tempfile.mkdtemp()
root = os.path.join(work, "sessions")
missing = os.path.join(work, "not-exist")
keys = os.path.join(work, "keys.txt")
os.makedirs(root)


def keygen(path: str) -> None:
    subprocess.run(["age-keygen", "-o", path], check=True, capture_output=True)


def sa(
    *args,
    key: str | None = None,
    path_prefix: str | None = None,
    roots: str | None = None,
    **kw,
):
    env = dict(os.environ)
    env.update(
        SESSION_ARCHIVE_ROOTS=roots or f"{root}\n{missing}",
        SESSION_ARCHIVE_DAYS="30",
        SESSION_ARCHIVE_KEY_FILE=key or keys,
    )
    if path_prefix:
        env["PATH"] = path_prefix + os.pathsep + env["PATH"]
    return subprocess.run(
        [sys.executable, SCRIPT, *args],
        capture_output=True,
        text=True,
        env=env,
        check=False,
        **kw,
    )


def body(tag: str) -> str:
    return "".join(f"{SECRET} {tag} line {i}\n" for i in range(3000))


def mk(rel: str, days_ago: float, tag: str | None = None) -> str:
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(body(tag or rel))
    t = NOW - days_ago * DAY
    os.utime(path, (t, t))
    return path


def read(rel: str) -> str:
    with open(os.path.join(root, rel)) as f:
        return f.read()


def exists(rel: str) -> bool:
    return os.path.lexists(os.path.join(root, rel))


def vols() -> list[str]:
    return sorted(n for n in os.listdir(root) if n.endswith(".tar.zst.age"))


def leftovers() -> list[str]:
    return [
        os.path.join(d, n)
        for d, _, fs in os.walk(root)
        for n in fs
        if n.endswith(".part")
    ]


def shim(name: str, script: str) -> str:
    d = os.path.join(work, "shim-" + name)
    os.makedirs(d)
    real = shutil.which("zstd")
    path = os.path.join(d, "zstd")
    with open(path, "w") as f:
        f.write("#!/usr/bin/env bash\n" + script.replace("@REAL@", real))
    os.chmod(path, 0o755)
    return d


try:
    keygen(keys)
    M1, M2, M_NOW = month(100), month(200), month(10)
    check(len({M1, M2, M_NOW}) == 3, "测试月份必须互不相同")

    # 已封存月份 M1（100 天前）与 M2（200 天前），以及未封存的当月
    mk("proj/old.jsonl", 100)
    mk("proj/artifacts/old.md", 100)
    mk("proj/sub/deep/x.log", 100)
    mk("proj/.DS_Store", 100)
    mk("proj/old.jsonl.lock.os", 100)
    mk("proj2/older.jsonl", 200)
    mk("proj/new.jsonl", 10)
    mk("sessions.db", 100)
    mk("stray.bin", 100)

    # 1. dry-run 只统计，不写不删
    r = sa("run", "--dry-run")
    check(r.returncode == 0, f"dry-run 退出码: {r.stderr}")
    check(
        f"{M1}: 3 个文件" in r.stdout and "将封存" in r.stdout,
        f"dry-run 应报告 {M1} 将封存 3 个文件: {r.stdout}",
    )
    check(
        f"{M_NOW}: 1 个文件" in r.stdout and "起可封存" in r.stdout,
        f"dry-run 应报告 {M_NOW} 等待: {r.stdout}",
    )
    check(not vols() and exists("proj/old.jsonl"), "dry-run 改动了文件")
    ok("dry-run 只统计")

    # 2. 封存：原文件被删，空目录被清，排除规则与未封存月份不动
    r = sa("run")
    check(r.returncode == 0, f"run 失败: {r.stdout}{r.stderr}")
    check(
        vols() == sorted([f"archive-{M1}.tar.zst.age", f"archive-{M2}.tar.zst.age"]),
        f"分卷: {vols()}",
    )
    for idx in (f"archive-{M1}.idx.age", f"archive-{M2}.idx.age"):
        check(exists(idx), f"缺少清单 {idx}")
    for gone in (
        "proj/old.jsonl",
        "proj/artifacts/old.md",
        "proj/sub/deep/x.log",
        "proj2/older.jsonl",
    ):
        check(not exists(gone), f"应已归档并删除: {gone}")
    check(
        not exists("proj/sub") and not exists("proj2") and not exists("proj/artifacts"),
        "变空的子目录应被清掉",
    )
    for kept in (
        "proj/new.jsonl",
        "proj/.DS_Store",
        "proj/old.jsonl.lock.os",
        "sessions.db",
        "stray.bin",
    ):
        check(exists(kept), f"不该归档的文件被动了: {kept}")
    for v in [*vols(), f"archive-{M1}.idx.age"]:
        with open(os.path.join(root, v), "rb") as f:
            check(SECRET.encode() not in f.read(), f"归档含明文: {v}")
    check(not leftovers(), "不应残留 .part")
    ok("封存、排除规则、空目录清理、无明文")

    # 3. 幂等
    before = {v: os.stat(os.path.join(root, v)).st_mtime_ns for v in vols()}
    r = sa("run")
    check(
        r.returncode == 0 and "封存" not in r.stdout.replace("将封存", ""),
        f"二次运行应无事可做: {r.stdout}",
    )
    check(
        before == {v: os.stat(os.path.join(root, v)).st_mtime_ns for v in vols()},
        "二次运行改动了归档卷",
    )
    ok("幂等")

    # 4. list
    r = sa("list")
    check(
        r.returncode == 0
        and f"archive-{M1}.tar.zst.age" in r.stdout
        and "3 个文件" in r.stdout,
        f"list: {r.stdout}{r.stderr}",
    )
    r = sa("list", os.path.join(root, f"archive-{M2}.tar.zst.age"))
    check("proj2/older.jsonl" in r.stdout, f"list 归档卷: {r.stdout}")
    ok("list")

    # 5. restore 单个文件：内容一致，mtime 为现在，不覆盖已存在文件，归档卷保持不变
    r = sa("restore", os.path.join(root, "proj/old.jsonl"))
    check(
        r.returncode == 0 and read("proj/old.jsonl") == body("proj/old.jsonl"),
        f"restore 内容: {r.stdout}{r.stderr}",
    )
    check(
        time.time() - os.stat(os.path.join(root, "proj/old.jsonl")).st_mtime < 300,
        "还原文件 mtime 应为现在",
    )
    check(not exists("proj/artifacts/old.md"), "只应还原指定的文件")
    with open(os.path.join(root, "proj/old.jsonl"), "w") as f:
        f.write("edited")
    sa("restore", os.path.join(root, "proj/old.jsonl"))
    check(read("proj/old.jsonl") == "edited", "restore 不应覆盖已存在的文件")
    check(len(vols()) == 2, "restore 不应改动归档卷")
    ok("restore 单个文件")

    # 6. restore 目录前缀与整卷；刚还原的文件不会被再次归档
    r = sa("restore", os.path.join(root, "proj/sub"))
    check(
        r.returncode == 0
        and read("proj/sub/deep/x.log") == body("proj/sub/deep/x.log"),
        f"restore 目录: {r.stderr}",
    )
    r = sa("restore", os.path.join(root, f"archive-{M1}.tar.zst.age"))
    check(
        r.returncode == 0
        and read("proj/artifacts/old.md") == body("proj/artifacts/old.md"),
        f"restore 整卷: {r.stderr}",
    )
    check(
        sa("restore", os.path.join(root, "proj/not-there.jsonl")).returncode != 0,
        "归档里没有的路径应报错",
    )
    check(
        sa("restore", os.path.join(work, "outside.txt")).returncode != 0,
        "不在根目录下的路径应报错",
    )
    r = sa("run")
    check(
        r.returncode == 0 and len(vols()) == 2 and exists("proj/artifacts/old.md"),
        "刚还原的文件不应被再次归档",
    )
    ok("restore 目录、整卷、错误路径")

    # 7. 重入：原文件与归档一致时只补删，不另写分卷；同名但内容不同则写新分卷
    t = NOW - 100 * DAY
    for rel in ("proj/artifacts/old.md", "proj/sub/deep/x.log"):
        os.utime(os.path.join(root, rel), (t, t))
    r = sa("run")
    check(
        r.returncode == 0 and len(vols()) == 2,
        f"一致的文件应只补删: {vols()} {r.stdout}",
    )
    check(
        not exists("proj/artifacts/old.md") and not exists("proj/sub/deep/x.log"),
        "一致的文件应被删除",
    )
    mk("proj/artifacts/old.md", 100, tag="changed")
    r = sa("run")
    check(
        r.returncode == 0 and f"archive-{M1}-2.tar.zst.age" in vols(),
        f"内容不同的文件应进新分卷: {vols()} {r.stdout}",
    )
    check(not exists("proj/artifacts/old.md"), "新分卷封存后应删原文件")
    mk("proj/late.jsonl", 100)
    # 迟到文件：封存月份里又出现旧 mtime 的文件
    sa("run")
    check(
        f"archive-{M1}-3.tar.zst.age" in vols() and not exists("proj/late.jsonl"),
        f"迟到文件应写分卷: {vols()}",
    )
    r = sa("restore", os.path.join(root, "proj/artifacts/old.md"))
    check(
        read("proj/artifacts/old.md") == body("changed"),
        "同名文件应还原最新分卷里的版本",
    )
    ok("重入与分卷")

    # 8. 校验失败：原文件保留，无归档与 .part 残留，退出码非零
    mk("proj3/bad.jsonl", 300)
    M3 = month(300)
    garbage = shim(
        "garbage",
        'for a in "$@"; do [ "$a" = -d ] && { echo garbage; exit 0; }; done\nexec @REAL@ "$@"\n',
    )
    r = sa("run", path_prefix=garbage)
    check(r.returncode != 0, "校验失败时 run 应非零退出")
    check(exists("proj3/bad.jsonl"), "校验失败时原文件必须保留")
    check(
        not any(M3 in v for v in os.listdir(root)) and not leftovers(),
        "校验失败后不应残留归档或 .part",
    )
    ok("校验失败保留原文件")

    # 9. 写入失败（根目录只读）：原文件保留
    mk("proj5/ro.jsonl", 400)
    os.chmod(root, stat.S_IRUSR | stat.S_IXUSR)
    try:
        r = sa("run")
    finally:
        os.chmod(root, stat.S_IRWXU)
    check(
        r.returncode != 0 and exists("proj5/ro.jsonl"),
        "写入失败时 run 应非零退出且原文件保留",
    )
    ok("写入失败保留原文件")

    # 10. 单个文件不可读：其余文件照常归档，不可读文件保留
    mk("proj6/ok.jsonl", 500)
    locked = mk("proj6/locked.jsonl", 500)
    mk("proj6/noenter/f.jsonl", 500)
    noenter = os.path.join(root, "proj6/noenter")
    os.chmod(locked, 0)
    os.chmod(noenter, stat.S_IRUSR)  # 可列出文件名、不可 lstat
    try:
        r = sa("run")
    finally:
        os.chmod(locked, 0o600)
        os.chmod(noenter, stat.S_IRWXU)
    check(r.returncode != 0 and "无法读取" in r.stderr, f"不可读文件应报错: {r.stderr}")
    check(
        exists("proj6/locked.jsonl")
        and exists("proj6/noenter/f.jsonl")
        and not exists("proj6/ok.jsonl"),
        "不可读文件保留，其余文件应归档",
    )
    ok("不可读文件不阻断其余")

    # 11. 中途被终止：不留 .part，原文件保留
    mk("proj7/slow.jsonl", 600)
    slow = shim(
        "slow",
        'for a in "$@"; do [ "$a" = -d ] && exec @REAL@ "$@"; done\nsleep 5\nexec @REAL@ "$@"\n',
    )
    env = dict(
        os.environ,
        SESSION_ARCHIVE_ROOTS=root,
        SESSION_ARCHIVE_DAYS="30",
        SESSION_ARCHIVE_KEY_FILE=keys,
    )
    env["PATH"] = slow + os.pathsep + env["PATH"]
    p = subprocess.Popen(
        [sys.executable, SCRIPT, "run"],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    for _ in range(100):
        if leftovers():
            break
        time.sleep(0.1)
    check(bool(leftovers()), "未观察到 .part，用例失效")
    p.send_signal(signal.SIGTERM)
    p.wait(timeout=30)
    time.sleep(0.5)
    check(
        not leftovers() and exists("proj7/slow.jsonl"),
        f"被终止后应清掉 .part 且保留原文件: {leftovers()}",
    )
    ok("中断清理")

    # 11b. 校验完成后、删除前文件被写入：保留被改写的文件，不丢新内容
    race = mk("proj8/race.jsonl", 700)
    cnt = os.path.join(work, "cnt")
    racer = shim(
        "race",
        'for a in "$@"; do [ "$a" = -d ] && exec @REAL@ "$@"; done\n'
        f"n=$(cat {cnt} 2>/dev/null || echo 0); n=$((n+1)); echo $n > {cnt}\n"
        f"[ $n = 2 ] && echo LATE >> {race}\n"  # 第 2 次压缩是写清单，在 verify 之后
        'exec @REAL@ "$@"\n',
    )
    r = sa("run", path_prefix=racer)
    check(os.path.exists(cnt), "用例失效: 垫片未被调用")
    check(
        exists("proj8/race.jsonl") and read("proj8/race.jsonl").endswith("LATE\n"),
        "校验后被写入的文件必须保留",
    )
    ok("校验后被写入的文件不被删")

    # 11c. 同一根目录不允许两个归档进程并行
    mk("proj9/lock.jsonl", 600)
    p = subprocess.Popen(
        [sys.executable, SCRIPT, "run"],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    for _ in range(100):
        if leftovers():
            break
        time.sleep(0.1)
    check(bool(leftovers()), "未观察到 .part，用例失效")
    r = sa("run")
    check(
        r.returncode != 0 and "已有另一个" in r.stderr,
        f"并行的第二个 run 应拒绝: {r.stderr}",
    )
    p.send_signal(signal.SIGTERM)
    p.wait(timeout=30)
    ok("并发 run 被锁拒绝")

    # 12. 换钥：密钥文件加入第二把后 rekey，只留新私钥仍可 list 与 restore
    sa("run")  # 把前面保留下来的文件正常封存
    k2 = os.path.join(work, "k2.txt")
    keygen(k2)
    with open(keys, "a") as f, open(k2) as g:
        f.write(g.read())
    r = sa("rekey")
    check(r.returncode == 0, f"rekey 失败: {r.stdout}{r.stderr}")
    check(sa("list", key=k2).returncode == 0, "rekey 后新私钥应能读清单")
    r = sa("restore", os.path.join(root, "proj2/older.jsonl"), key=k2)
    check(
        r.returncode == 0 and read("proj2/older.jsonl") == body("proj2/older.jsonl"),
        f"rekey 后新私钥应能还原: {r.stderr}",
    )
    ok("rekey 与密钥轮换")

    # 13. 还原整个根目录
    os.unlink(os.path.join(root, "proj2/older.jsonl"))
    r = sa("restore", root, key=k2)
    check(
        r.returncode == 0 and read("proj2/older.jsonl") == body("proj2/older.jsonl"),
        f"restore <根目录> 应还原全部: {r.stderr}",
    )
    ok("restore 根目录")

    # 13b. 还原期间别处新建了同名文件：不覆盖
    raced = os.path.join(root, "proj9/lock.jsonl")
    os.unlink(raced)
    py = (
        "import sys,time;d=sys.stdin.buffer;o=sys.stdout.buffer;"
        "o.write(d.read(20000));o.flush();b=d.read();len(b)>50000 and time.sleep(2);o.write(b)"
    )
    slow_dec = shim(
        "slowdec",
        f'for a in "$@"; do [ "$a" = -d ] && {{ @REAL@ "$@" | {sys.executable} -c \'{py}\'; exit; }}; done\n'
        'exec @REAL@ "$@"\n',
    )
    p = subprocess.Popen(
        [sys.executable, SCRIPT, "restore", raced],
        env=dict(env, PATH=slow_dec + os.pathsep + os.environ["PATH"]),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    for _ in range(200):
        if leftovers():
            break
        time.sleep(0.1)
    check(
        bool(leftovers()),
        f"未观察到 restore 的 .part，用例失效: rc={p.poll()} {p.stderr.read() if p.poll() is not None else ''}",
    )
    with open(raced, "w") as f:
        f.write("NEW")
    p.wait(timeout=60)
    check(read("proj9/lock.jsonl") == "NEW", "还原不得覆盖期间新建的文件")
    check(not leftovers(), "还原后不应残留 .part")
    ok("restore 不覆盖期间新建的文件")

    # 14. 还原不跟随目录符号链接
    outside = os.path.join(work, "outside")
    os.makedirs(outside)
    shutil.rmtree(os.path.join(root, "proj2"))
    os.symlink(outside, os.path.join(root, "proj2"))
    r = sa("restore", os.path.join(root, "proj2/older.jsonl"), key=k2)
    check(
        r.returncode != 0 and not os.listdir(outside),
        f"符号链接目录下的还原必须拒绝且不写外部: {os.listdir(outside)}",
    )
    ok("restore 拒绝符号链接")

    # 15. 一个根目录无法加锁：计入失败，其余根目录照常归档
    ro = os.path.join(work, "ro-root")
    os.makedirs(ro)
    mk("proj10/x.jsonl", 700)
    os.chmod(ro, stat.S_IRUSR | stat.S_IXUSR)
    try:
        r = sa("run", roots=f"{ro}\n{root}")
    finally:
        os.chmod(ro, stat.S_IRWXU)
    check(
        r.returncode != 0
        and "Traceback" not in r.stderr
        and not exists("proj10/x.jsonl"),
        f"加锁失败的根目录不应阻断其余根目录: {r.stderr}",
    )
    ok("锁文件创建失败不阻断其余根目录")

    print("ALL PASSED")
finally:
    os.chmod(root, stat.S_IRWXU)
    shutil.rmtree(work, ignore_errors=True)
