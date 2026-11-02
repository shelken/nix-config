"""microsandbox 的 msb 命令行：sb 与 VM 之间的唯一 seam。

create、start 会经 sec-run 注入宿主凭据（secrets 占位符替换要它）；其余命令直接跑。
测试用一个假的 msb 放进 PATH 就能驱动整个生命周期，不需要 VM。
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import time
from typing import Any

from .config import Config, SbError


class Msb:
    def __init__(self, cfg: Config):
        self._cfg = cfg
        self._bin: str | None = None

    @property
    def bin(self) -> str:
        if self._bin is None:
            found = shutil.which("msb")
            if not found:
                raise SbError("PATH 中没有 msb（用 mise 安装 microsandbox，并确认 mise 已激活）")
            self._bin = found
        return self._bin

    def run(self, *args: str, to_stderr: bool = False) -> int:
        """继承 stdio 运行，返回退出码。to_stderr 把 msb 的 stdout 转到 stderr（sb 的 stdout 留给机器可读输出）。"""
        cmd = [self.bin, *args]
        if args[0] in ("create", "start") and self._cfg.host_credentials and shutil.which("sec-run"):
            cmd = ["sec-run", *cmd]
        rc = subprocess.run(cmd, stdout=sys.stderr if to_stderr else None).returncode
        return 128 - rc if rc < 0 else rc  # 被信号杀死按 shell 惯例是 128+信号号

    def capture(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run([self.bin, *args], capture_output=True, text=True)

    def inspect(self, name: str) -> dict[str, Any] | None:
        r = self.capture("inspect", name, "--format", "json")
        if r.returncode != 0:
            return None
        try:
            return json.loads(r.stdout)
        except json.JSONDecodeError:
            return None

    def must(self, *args: str, to_stderr: bool = False) -> None:
        """run 的严格版：msb 自己已把原因打到终端，这里只补一句是哪条命令失败。"""
        rc = self.run(*args, to_stderr=to_stderr)
        if rc != 0:
            raise SbError(f"msb {args[0]} 失败 (退出码 {rc})")

    def status(self, name: str) -> str:
        return (self.inspect(name) or {}).get("status") or ""

    def wait_running(self, name: str, attempts: int = 30) -> None:
        for _ in range(attempts):
            if self.status(name) == "Running":
                return
            time.sleep(0.5)
        raise SbError(f"等待 VM {name} 达到 Running 状态超时")
