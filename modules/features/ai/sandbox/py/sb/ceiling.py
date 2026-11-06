"""能力上限 sb.yaml：一次解析成带类型的 Ceiling，其余模块不再读 YAML 原文。"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from typing import Any

from .errors import SbError
from .yamlio import load_mapping, mapping, str_list

IP = r"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"
IP_PORT = re.compile(rf"^{IP}:[0-9]+$")
IP_OR_IP_PORT = re.compile(rf"^{IP}(:[0-9]+)?$")

DEFAULT_NETWORK = {"policy": "public", "allow": ["public", "dns"]}


def expand_path(p: str, home: str) -> str:
    if p == "~" or p.startswith("~/"):
        p = home + p[1:]
    return p.replace("${HOME}", home)


def under(root: str, p: str) -> bool:
    return p == root or p.startswith(root + "/")


@dataclass(frozen=True)
class Ceiling:
    image: str
    cpus: int
    memory: str
    volume_name: str
    volume_size: str
    mount_roots: list[str]  # 已展开 ~ 与 ${HOME}，未 realpath
    network: dict[str, Any]  # 交给 msb 的 VM 级网络策略，不含 default_grant
    default_grants: list[str]  # 所有上下文默认放行的私网 IP:端口
    default_allow: list[str]  # 所有上下文默认放行的宿主端口，形如 host:tcp:8317
    secrets: dict[str, Any]

    @staticmethod
    def load(path: str, home: str) -> "Ceiling":
        if not os.path.isfile(path):
            raise SbError(f"找不到全局能力上限配置文件: {path}")
        raw = load_mapping(path)

        network = dict(mapping(raw.get("network"), "sb.yaml 的 network") or DEFAULT_NETWORK)
        grants = str_list(network.pop("default_grant", None), "sb.yaml 的 network.default_grant")
        for grant in grants:
            if not IP_PORT.match(grant):
                raise SbError(f"sb.yaml network.default_grant 只接受 IP:端口: {grant}")
        allow = str_list(network.get("allow"), "sb.yaml 的 network.allow")

        volume = mapping(raw.get("volume"), "sb.yaml 的 volume")
        return Ceiling(
            image=raw.get("image") or "ubuntu",
            cpus=raw.get("cpus") or 4,
            memory=raw.get("memory") or "8G",
            volume_name=volume.get("name") or "sb-main-data",
            volume_size=volume.get("size") or "8G",
            mount_roots=[expand_path(r, home) for r in str_list(raw.get("mount_roots"), "sb.yaml 的 mount_roots")],
            network=network,
            default_grants=grants,
            default_allow=[a for a in allow if a.startswith("host:tcp:")],
            secrets=mapping(raw.get("secrets"), "sb.yaml 的 secrets"),
        )
