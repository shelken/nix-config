"""宿主配置：Nix 生成的 sb-config.json，是 sb 读取外部事实的唯一入口。

sb 的其余模块都不碰 os.environ。验证与测试换一份 sb-config.json 即可
改变目录、策略文件与凭据行为；MSB_HOME、MSB_CONFIG_PATH 是 msb 自己的变量，优先于文件里的值。
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from functools import cached_property
from typing import Mapping

from .ceiling import Ceiling
from .errors import SbError

VM_NAME = "sb-main"


@dataclass(frozen=True)
class Config:
    msb_home: str
    policy_yaml: str
    publish_dir: str
    launcher: str
    guest_status: str
    sync_lock: str
    guest_sync: str
    guest_config_mount: str
    guest_contexts_dir: str
    guest_data_dir: str
    mise_host_dir: str
    mise_guest_mount: str
    host_credentials: bool
    home: str
    msb_env: Mapping[str, str]  # msb 子进程的环境：调用者环境加上解析后的 MSB_HOME、MSB_CONFIG_PATH，不依赖用户 shell 是否导出

    @property
    def approval_dir(self) -> str:
        return os.path.join(self.msb_home, "approvals")

    @property
    def lock_dir(self) -> str:
        return os.path.join(self.msb_home, "locks")

    @cached_property
    def ceiling(self) -> Ceiling:
        return Ceiling.load(self.policy_yaml, self.home)

    @staticmethod
    def load(env: Mapping[str, str] = os.environ) -> "Config":
        path = env.get("SB_CONFIG_FILE")
        if not path:
            raise SbError("缺少 SB_CONFIG_FILE：sb 必须经 Nix 打包的入口运行")
        with open(path, encoding="utf-8") as f:
            nix = json.load(f)
        msb_config = env.get("MSB_CONFIG_PATH") or nix["msb_config"]
        msb_home = env.get("MSB_HOME") or nix["msb_home"]
        guest = nix["guest"]
        return Config(
            msb_home=msb_home,
            policy_yaml=nix["policy_yaml"],
            publish_dir=nix["publish_dir"],
            launcher=nix["launcher"],
            guest_status=nix["guest_status"],
            sync_lock=nix["sync_lock"],
            guest_sync=nix["guest_sync"],
            guest_config_mount=guest["config_mount"],
            guest_contexts_dir=guest["contexts_dir"],
            guest_data_dir=guest["data_dir"],
            mise_host_dir=nix["mise"]["host_dir"],
            mise_guest_mount=nix["mise"]["guest_mount"],
            host_credentials=nix["host_credentials"],
            home=env.get("HOME", ""),
            msb_env={**env, "MSB_HOME": msb_home, "MSB_CONFIG_PATH": msb_config},
        )
