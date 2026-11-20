from __future__ import annotations

import json
import shutil
import subprocess
import sys
import time
from typing import Any

from .config import Config
from .errors import SbError


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
        cmd = [self.bin, *args]
        env = self._cfg.msb_env
        if args[0] in ("create", "start") and self._cfg.host_credentials:
            env = {**env, **self._host_secrets()}
            if shutil.which("sec-run"):
                cmd = ["sec-run", *cmd]
        rc = subprocess.run(cmd, stdout=sys.stderr if to_stderr else None, env=env).returncode
        return 128 - rc if rc < 0 else rc  # 被信号杀死按 shell 惯例是 128+信号号

    def _host_secrets(self) -> dict[str, str]:
        secrets = {}
        for name, path in self._cfg.host_secret_files.items():
            try:
                with open(path, encoding="utf-8") as f:
                    secrets[name] = f.read().strip()
            except OSError as e:
                raise SbError(f"读不到宿主凭据 {name}（{path}）：{e.strerror}") from e
        return secrets

    def capture(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run([self.bin, *args], capture_output=True, text=True, env=self._cfg.msb_env)

    def inspect(self, name: str) -> dict[str, Any] | None:
        r = self.capture("inspect", name, "--format", "json")
        if r.returncode != 0:
            return None
        try:
            return json.loads(r.stdout)
        except json.JSONDecodeError:
            return None

    def must(self, *args: str, to_stderr: bool = False) -> None:
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
