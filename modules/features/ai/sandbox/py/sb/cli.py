"""sb 子命令分发。每个子命令一个函数，返回进程退出码。"""

from __future__ import annotations

import json
import os
import random
import signal
import subprocess
import sys
import time

from . import approvals, sync, vm
from .config import VM_NAME, Config, SbError
from .msb import Msb
from .plan import PlanError, Plan, resolve_plan

USAGE = """用法:
sb up                创建或启动主 VM (sb-main)，已运行且上限一致则复用，上限变化且空闲则重建
sb down              停止主 VM
sb rm [--force]       删除主 VM，保留数据卷；有运行中上下文时拒绝，--force 强制删除
sb sync              补齐沙箱内的 mise 工具与 OMP 插件 (幂等，只装缺失项；宿主写锁串行化)
sb status            查看主 VM 状态、规格、能力上限指纹一致性与缺失工具
sb plan [--json]     显示当前项目解析后的授权：挂载、导入、放行的私网目标与批准状态
sb trust             批准当前项目的 .sandbox.yaml (内容哈希变了要重新批准)
sb run [-t] CMD…     在当前项目执行上下文内运行命令 (TTY 自适应)
sb shell             进入当前项目执行上下文的交互式 Bash shell"""


def _plan(cfg: Config) -> Plan:
    return resolve_plan(os.getcwd(), cfg.policy_yaml, home=cfg.home)


def up(cfg: Config, msb: Msb, args: list[str]) -> int:
    with vm.lifecycle_lock(cfg, "启动/重建"):
        vm.ensure(cfg, msb)
    return 0


def down(cfg: Config, msb: Msb, args: list[str]) -> int:
    with vm.lifecycle_lock(cfg, "停止"):
        print(f"[sb] 正在停止主 VM {VM_NAME}...", file=sys.stderr)
        return msb.run("stop", VM_NAME, *args)


def rm(cfg: Config, msb: Msb, args: list[str]) -> int:
    force = any(a in ("--force", "-f") for a in args)
    rest = [a for a in args if a not in ("--force", "-f")]
    with vm.lifecycle_lock(cfg, "删除"):
        if not force:
            try:
                n = vm.count_contexts(cfg, msb)
            except vm.BusyQueryError as e:
                raise SbError(f"无法确认主 VM {VM_NAME} 是否有上下文在运行，拒绝删除。原因: {e}") from None
            if n > 0:
                raise SbError(f"主 VM {VM_NAME} 有 {n} 个上下文在运行，拒绝删除。可用 sb rm --force 强制")
        print(f"[sb] 正在删除主 VM {VM_NAME} (保留数据卷)...", file=sys.stderr)
        return msb.run("rm", "--force", VM_NAME, *rest)


def status(cfg: Config, msb: Msb, args: list[str]) -> int:
    print(vm.status_report(cfg, msb))
    return 0


def plan(cfg: Config, msb: Msb, args: list[str]) -> int:
    p = _plan(cfg)
    if args[:1] in (["--json"], ["-j"]):
        print(json.dumps({**json.loads(p.to_json()), "approval": approvals.state(cfg, p.project_root)}, ensure_ascii=False, indent=2))
    else:
        print(approvals.render(cfg, p))
    return 0


def trust(cfg: Config, msb: Msb, args: list[str]) -> int:
    p = _plan(cfg)
    if not os.path.isfile(os.path.join(p.project_root, ".sandbox.yaml")):
        print(f"[sb] {p.project_root} 没有 .sandbox.yaml，不需要批准")
        return 0
    h = approvals.approve(cfg, p.project_root)
    print(approvals.render(cfg, p))
    print(f"[+] 已批准 {p.project_root}/.sandbox.yaml ({h[:12]})")
    return 0


def sync_cmd(cfg: Config, msb: Msb, args: list[str]) -> int:
    return sync.run(cfg, msb, args)


def run(cfg: Config, msb: Msb, args: list[str]) -> int:
    if sys.stdin.isatty() and sys.stdout.isatty():
        terminal = ["-t"]
    elif sys.stdin.isatty():
        terminal = ["--stream", "--no-stdin"]
    else:
        terminal = ["--stream"]
    while args:
        if args[0] == "-t":
            terminal, args = ["-t"], args[1:]
        elif args[0] == "--":
            args = args[1:]
            break
        else:
            break
    if not args:
        raise SbError("sb run 需要提供待执行的命令。示例: sb run git status")

    cwd = os.getcwd()
    p = resolve_plan(cwd, cfg.policy_yaml, home=cfg.home)
    if approvals.state(cfg, p.project_root) == "unapproved":
        raise SbError(f"{p.project_root}/.sandbox.yaml 未批准，或批准后已变更。先执行 sb plan 查看授权内容，确认后执行 sb trust")
    ctx_id = f"ctx_{int(time.time())}_{random.randrange(32768)}"

    with vm.lifecycle_lock(cfg, "启动"):
        vm.ensure(cfg, msb)

    if p.imports:
        _stage_imports(msb, ctx_id, p)

    # Ctrl-C 会发给整个前台进程组，让子进程自己处理并把退出码传回来，父进程只是不抛 KeyboardInterrupt。
    # 用空处理函数而不是 SIG_IGN：忽略的信号会被 exec 继承，子进程就再也停不下来
    old = signal.signal(signal.SIGINT, lambda *_: None)
    try:
        return msb.run("exec", VM_NAME, *terminal, "--", "bash", cfg.launcher, ctx_id, p.to_json(), cwd, *args)
    finally:
        signal.signal(signal.SIGINT, old)


def _stage_imports(msb: Msb, ctx_id: str, p: Plan) -> None:
    """把 imports 复制进 VM 里本次上下文的暂存目录。launcher 接手之前任何失败都要回收暂存目录。"""
    guest_dir = f"/run/sandbox/contexts/{ctx_id}"
    stages = sorted({i.stage for i in p.imports})
    try:
        msb.must(
            "exec", VM_NAME, "--", "bash", "-c", 'mkdir -p "${@:2}" && touch "$1"', "_",
            f"{guest_dir}/starting", *[f"{guest_dir}/imports/{s}" for s in stages],
        )  # fmt: skip
        for imp in p.imports:
            msb.must("copy", imp.src, f"{VM_NAME}:{guest_dir}/imports/{imp.stage}/{imp.target.rsplit('/', 1)[-1]}", to_stderr=True)
        msb.must("exec", VM_NAME, "--", "chmod", "-R", "u+rwX,go-rwx", f"{guest_dir}/imports")
    except BaseException:
        subprocess.run([msb.bin, "exec", VM_NAME, "--", "rm", "-rf", guest_dir], capture_output=True)
        raise


COMMANDS = {
    "up": up,
    "down": down,
    "rm": rm,
    "status": status,
    "plan": plan,
    "trust": trust,
    "sync": sync_cmd,
    "run": run,
}


def main(argv: list[str]) -> int:
    cmd, args = (argv[0], argv[1:]) if argv else ("", [])
    if cmd in ("-h", "--help", "help"):
        print(USAGE)
        return 0
    if cmd == "shell":
        cmd, args = "run", ["-t", "bash", *args]
    if cmd not in COMMANDS:
        print(USAGE)
        return 1
    try:
        cfg = Config.load()
        return COMMANDS[cmd](cfg, Msb(cfg), args)
    except (SbError, PlanError) as e:
        print(f"[-] 错误: {e}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
