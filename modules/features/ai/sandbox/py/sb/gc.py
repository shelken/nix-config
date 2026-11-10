"""sb gc：用户主动触发的共用层回收，与补齐 (sync) 的幂等语义分离。

与 sync 共用同一把写锁：两者都写共用安装层，必须互斥；单开一把锁反而允许并发。
"""

from __future__ import annotations

import sys

from .config import VM_NAME, Config
from .locks import LockTimeout, flock
from .msb import Msb


def run_locked(cfg: Config, msb: Msb, *, to_stderr: bool = False) -> int:
    try:
        with flock(cfg.sync_lock, 600):
            return msb.run(
                "exec", VM_NAME, "--stream", "--no-stdin", "--", "bash", cfg.guest_gc, to_stderr=to_stderr
            )
    except LockTimeout:
        print(f"[-] 错误: 获取共用 mise 目录写锁超时 (600s): {cfg.sync_lock}", file=sys.stderr)
        return 1
