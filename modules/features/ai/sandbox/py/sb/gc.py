"""sb gc：用户主动触发的共用层回收，与补齐 (sync) 的幂等语义分离。

与 sync 共用同一把写锁：两者都写共用安装层，必须互斥；单开一把锁反而允许并发。
"""

from __future__ import annotations

import sys

from .config import VM_NAME, Config
from .locks import LockTimeout, flock
from .msb import Msb


def run_locked(cfg: Config, msb: Msb, *, dry_run: bool, to_stderr: bool = False) -> int:
    # dry-run 与真删走同一个 guest 脚本，只用环境变量区分，避免两条代码路径各自演化
    env = ("env", "SB_GC_DRY_RUN=1") if dry_run else ()
    try:
        with flock(cfg.sync_lock, 600):
            return msb.run(
                "exec", VM_NAME, "--stream", "--no-stdin", "--", *env, "bash", cfg.guest_gc, to_stderr=to_stderr
            )
    except LockTimeout:
        print(f"[-] 错误: 获取共用 mise 目录写锁超时 (600s): {cfg.sync_lock}", file=sys.stderr)
        return 1
