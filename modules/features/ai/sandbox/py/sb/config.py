"""宿主配置：Nix 生成的 sb-config.json 加少量环境变量覆盖，是 sb 读取外部事实的唯一入口。

sb 的其余模块都不碰 os.environ。覆盖变量只服务测试与验证（一次性 MSB_HOME、隔离的发布目录等），
日常使用只有 sb-config.json。
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from typing import Mapping

VM_NAME = "sb-main"


class SbError(Exception):
    """用户可处理的失败。str(e) 是 `[-] 错误:` 之后的完整正文。"""


@dataclass(frozen=True)
class Config:
    msb_config: str
    msb_home: str
    policy_yaml: str  # 能力上限 sb.yaml
    sandbox_config: str | None  # 覆盖发布目录（~/.config/sandbox）的位置，None 表示用默认
    launcher: str
    guest_status: str
    mise_host_dir: str
    mise_guest_mount: str
    mise_mount_mode: str
    mise_lock_dir: str
    host_credentials: bool
    home: str

    @property
    def approval_dir(self) -> str:
        return os.path.join(self.msb_home, "approvals")

    @property
    def lock_dir(self) -> str:
        return os.path.join(self.msb_home, "locks")

    @property
    def mise_mount_spec(self) -> str:
        return f"{self.mise_guest_mount}:{self.mise_mount_mode}"

    @staticmethod
    def load(env: Mapping[str, str] = os.environ) -> "Config":
        path = env.get("SB_CONFIG_FILE")
        if not path:
            raise SbError("缺少 SB_CONFIG_FILE：sb 必须经 Nix 打包的入口运行")
        with open(path, encoding="utf-8") as f:
            nix = json.load(f)
        home = env.get("HOME", "")
        policy = env.get("SB_CONFIG") or ""
        if not policy:
            user_yaml = os.path.join(home, ".config/sandbox/sb.yaml")
            policy = user_yaml if os.path.isfile(user_yaml) else nix["policy_yaml"]
        mise_host = env.get("SB_MISE_HOST_DIR") or nix["mise"]["host_dir"]
        return Config(
            msb_config=env.get("MSB_CONFIG_PATH") or nix["msb_config"],
            msb_home=env.get("MSB_HOME") or nix["msb_home"],
            policy_yaml=policy,
            sandbox_config=env.get("SB_SANDBOX_CONFIG") or None,
            launcher=nix["launcher"],
            guest_status=nix["guest_status"],
            mise_host_dir=mise_host,
            mise_guest_mount=nix["mise"]["guest_mount"],
            mise_mount_mode=nix["mise"]["mount_mode"],
            mise_lock_dir=env.get("SB_MISE_LOCK_DIR") or mise_host,
            host_credentials=env.get("SB_NO_HOST_CREDENTIALS", "0") != "1",
            home=home,
        )
