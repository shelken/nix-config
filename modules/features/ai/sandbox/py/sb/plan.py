"""执行计划 (Plan)：sb.yaml 能力上限 + 项目 .sandbox.yaml 授权解析成 host → guest 的唯一数据契约。

宿主这边由 resolve_plan 产出，guest 的 launcher 通过 PLAN_JSON 消费。字段就是 Plan 的属性，
改字段时 guest/plan.sh 要一起改，test_contract.py 用真实的 Plan 校验两边一致。
"""

from __future__ import annotations

import json
import os
import re
import subprocess
from dataclasses import asdict, dataclass, field
from typing import Any

from .ceiling import IP_OR_IP_PORT, Ceiling, expand_path, under
from .errors import SbError
from .yamlio import as_list, load_mapping, str_list


@dataclass
class Import:
    src: str
    target: str
    dir: str
    stage: int


@dataclass
class PathGrant:
    path: str
    readonly: bool


@dataclass
class Plan:
    project_root: str
    git_common_dir: str
    imports: list[Import] = field(default_factory=list)
    network: list[str] = field(default_factory=list)
    paths: list[PathGrant] = field(default_factory=list)
    default_allow: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    def to_json(self) -> str:
        return json.dumps(self.to_dict(), ensure_ascii=False, separators=(",", ":"))


def _under_any(roots: list[str], p: str) -> bool:
    return any(under(r, p) for r in roots)


def _git(cwd: str, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True)


_IMPORT_TARGET = re.compile(r"^(~/|/)[^/]")


def resolve_plan(cwd: str, ceiling: Ceiling, home: str) -> Plan:
    allowed_roots = [os.path.realpath(r) for r in ceiling.mount_roots if os.path.isdir(r)]

    in_git = _git(cwd, "rev-parse", "--is-inside-work-tree").returncode == 0
    project_root = ""
    if in_git:
        project_root = _git(cwd, "rev-parse", "--show-toplevel").stdout.strip()
    project_root = os.path.realpath(project_root or cwd)

    if not _under_any(allowed_roots, project_root):
        raise SbError(f"当前项目根目录 {project_root} 超出沙箱能力上限 (未落在 sb.yaml mount_roots 挂载根内)")

    git_common_dir = ""
    if in_git:
        raw = _git(cwd, "rev-parse", "--git-common-dir").stdout.strip()
        if raw:
            git_common_dir = os.path.realpath(os.path.join(cwd, raw))
    if git_common_dir and not under(project_root, git_common_dir) and not _under_any(allowed_roots, git_common_dir):
        raise SbError(f"worktree 的 git common dir {git_common_dir} 超出沙箱能力上限，请先把该路径加入 mount_roots")

    imports: list[Import] = []
    network: list[str] = []
    paths: list[PathGrant] = []

    proj_cfg = os.path.join(project_root, ".sandbox.yaml")
    if os.path.isfile(proj_cfg):
        cfg = load_mapping(proj_cfg)
        imports = _resolve_imports(as_list(cfg.get("imports"), ".sandbox.yaml 的 imports"), project_root, home)
        network = _resolve_network(str_list(cfg.get("network"), ".sandbox.yaml 的 network"))
        paths = _resolve_paths(as_list(cfg.get("paths"), ".sandbox.yaml 的 paths"), project_root, home, allowed_roots)

    if ceiling.default_grants:
        network = sorted(set(network + ceiling.default_grants))

    return Plan(
        project_root=project_root,
        git_common_dir=git_common_dir,
        imports=imports,
        network=network,
        paths=paths,
        default_allow=ceiling.default_allow,
    )


def _resolve_imports(items: list[Any], project_root: str, home: str) -> list[Import]:
    verified: list[tuple[str, str, str]] = []
    for item in items:
        src = item.get("src") if isinstance(item, dict) else None
        target = item.get("target") if isinstance(item, dict) else None
        if not isinstance(src, str) or not isinstance(target, str) or not src or not target:
            raise SbError(
                ".sandbox.yaml 的 imports 每项都要写 src 与 target: "
                + json.dumps(item, ensure_ascii=False, separators=(",", ":"))
            )
        rel = target.removeprefix("~/").removeprefix("/")
        if (
            not _IMPORT_TARGET.match(target)
            or target.endswith("/")
            or "/../" in f"/{target}/"
            or "/" not in rel
        ):
            raise SbError(f"imports 的 target 必须以 ~/ 或 / 开头、不含 ..、位于某个子目录内: {target}")
        src = expand_path(src, home)
        if not src.startswith("/"):
            src = f"{project_root}/{src}"
        if not os.path.isfile(src):
            raise SbError(f".sandbox.yaml 中声明的导入文件不存在: {src}")
        verified.append((os.path.realpath(src), target, re.sub(r"/[^/]*$", "", target, count=1)))

    seen: set[str] = set()
    for _, target, _ in sorted(verified, key=lambda v: v[1]):
        if target in seen:
            raise SbError(f"imports 的 target 重复: {target}")
        seen.add(target)

    dirs = sorted({d for _, _, d in verified})
    return [Import(src=s, target=t, dir=d, stage=dirs.index(d)) for s, t, d in verified]


def _resolve_network(targets: list[str]) -> list[str]:
    for target in targets:
        if not IP_OR_IP_PORT.match(target):
            raise SbError(f".sandbox.yaml 的 network 只接受 IP 或 IP:端口: {target}")
    return targets


def _resolve_paths(items: list[Any], project_root: str, home: str, allowed_roots: list[str]) -> list[PathGrant]:
    grants: list[PathGrant] = []
    for item in items:
        if isinstance(item, str):
            readonly = item.endswith(":ro")
            p = item.removesuffix(":ro")
        elif isinstance(item, dict) and isinstance(item.get("path"), str):
            unknown = set(item) - {"path", "readonly"}
            if unknown or not isinstance(item.get("readonly", False), bool):
                raise SbError(f".sandbox.yaml 的 paths 映射只接受 path 与布尔值 readonly: {json.dumps(item, ensure_ascii=False)}")
            p, readonly = item["path"], item.get("readonly", False)
        else:
            raise SbError(f".sandbox.yaml 的 paths 每项必须是路径字符串或带 path 的映射: {json.dumps(item, ensure_ascii=False)}")
        p = expand_path(p, home)
        if not p.startswith("/"):
            p = f"{project_root}/{p}"
        if not os.path.exists(p):
            raise SbError(f".sandbox.yaml 中声明的额外路径不存在: {p}")
        real = os.path.realpath(p)
        if not _under_any(allowed_roots, real):
            raise SbError(f".sandbox.yaml 中额外路径 {real} 超出能力上限 (未落在 mount_roots 内)")
        grants.append(PathGrant(path=real, readonly=readonly))
    return grants
