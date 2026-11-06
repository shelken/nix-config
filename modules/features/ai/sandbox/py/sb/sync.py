"""sb sync：在 VM 内补齐 mise 工具与 OMP 插件，宿主侧用共用目录下的锁串行化。

上下文里的 `mise install` 不拿这把锁（项目工具），只有 sync 写登记工具与插件缓存时才拿。
"""

from __future__ import annotations

import sys

from .config import VM_NAME, Config
from .locks import LockTimeout, flock
from .msb import Msb


def run_locked(cfg: Config, msb: Msb, *, to_stderr: bool = False) -> int:
    try:
        with flock(cfg.sync_lock, 600):
            return msb.run("exec", VM_NAME, "--stream", "--no-stdin", "--", "bash", cfg.guest_sync, to_stderr=to_stderr)
    except LockTimeout:
        print(f"[-] 错误: 获取共用 mise 目录写锁超时 (600s): {cfg.sync_lock}", file=sys.stderr)
        return 1
