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
    mise_url_replacements_file: str
    host_credentials: bool
    host_secret_files: Mapping[str, str]
    snapshot_cmd: tuple[str, ...]
    home: str
    msb_env: Mapping[str, str]

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
            mise_url_replacements_file=nix["mise"]["url_replacements_file"],
            host_credentials=nix["host_credentials"],
            host_secret_files=nix["host_secret_files"],
            snapshot_cmd=tuple(nix["snapshot_cmd"]),
            home=env.get("HOME", ""),
            msb_env={**env, "MSB_HOME": msb_home, "MSB_CONFIG_PATH": msb_config},
        )
