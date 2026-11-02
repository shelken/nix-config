"""sb sync：在 VM 内补齐 mise 工具与 OMP 插件，宿主侧用共用目录下的 .sync.lock 串行化。

上下文里的 `mise install` 不拿这把锁（项目工具），只有 sync 写登记工具与插件缓存时才拿。
"""

from __future__ import annotations

import os
import sys

from .config import VM_NAME, Config, SbError
from .locks import LockTimeout, flock
from .msb import Msb

_GUEST_SYNC = """
if [[ -f /run/sandbox-config/current/sync-guest.sh ]]; then
  exec bash /run/sandbox-config/current/sync-guest.sh "$@"
else
  echo "[!] 警告: 未在沙箱内找到 sync-guest.sh，跳过自动补齐" >&2
  exit 1
fi
"""


def run_locked(cfg: Config, msb: Msb, vm: str, args: list[str], *, to_stderr: bool = False) -> int:
    lock = os.path.join(cfg.mise_lock_dir, ".sync.lock")
    try:
        with flock(lock, 600):
            return msb.run("exec", vm, "--stream", "--no-stdin", "--", "bash", "-c", _GUEST_SYNC, "argv0", *args, to_stderr=to_stderr)
    except LockTimeout:
        print(f"[-] 错误: 获取共用 mise 目录写锁超时 (600s): {lock}", file=sys.stderr)
        return 1


def run(cfg: Config, msb: Msb, args: list[str]) -> int:
    from . import vm as vmmod  # vm.ensure 在首次创建时也要 sync，两边互相引用

    vm = VM_NAME
    if args and not args[0].startswith("-"):
        vm, args = args[0], args[1:]
    if msb.inspect(vm) is None:
        print(f"[sb] VM {vm} 尚未创建，正在自动启动...", file=sys.stderr)
        with vmmod.lifecycle_lock(cfg, "启动"):
            vmmod.ensure(cfg, msb)
    elif msb.status(vm) != "Running":
        print(f"[sb] VM {vm} 处于停止状态，正在启动...", file=sys.stderr)
        with vmmod.lifecycle_lock(cfg, "启动"):
            msb.must("start", vm)
            msb.wait_running(vm)
    print(f"[sb] 正在沙箱 {vm} 内执行工具与插件补齐 (sb sync)...", file=sys.stderr)
    return run_locked(cfg, msb, vm, args)
