"""执行计划 (Plan)：sb.yaml 能力上限 + 项目 .sandbox.yaml 授权解析成 host → guest 的唯一数据契约。

宿主这边由 resolve_plan 产出，guest 的 launcher 通过 PLAN_JSON 消费。字段就是 Plan 的属性，
改字段时 guest/ 下读取它的脚本要一起改。

YAML 一律经 yq 转 JSON：批准哈希（sb trust）用的也是 yq，换解析器会让 YAML 1.1 与 1.2 的差异
（yes/no、八进制、冒号分隔的整数）悄悄改变授权内容。
"""

from __future__ import annotations

import json
import os
import re
import subprocess
from dataclasses import asdict, dataclass, field
from typing import Any, Callable


class PlanError(Exception):
    """授权内容不合法或超出能力上限。str(e) 是给用户看的完整报错。"""


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
    cwd: str
    imports: list[Import] = field(default_factory=list)
    network: list[str] = field(default_factory=list)
    paths: list[PathGrant] = field(default_factory=list)
    default_allow: list[str] = field(default_factory=list)

    def to_json(self) -> str:
        return json.dumps(asdict(self), ensure_ascii=False, separators=(",", ":"))


def load_yaml(path: str) -> Any:
    r = subprocess.run(["yq", "-o=json", ".", path], capture_output=True, text=True)
    if r.returncode != 0:
        raise PlanError(f"无法解析 {path}: {r.stderr.strip()}")
    return json.loads(r.stdout)


def expand_path(p: str, home: str) -> str:
    # 只替换开头的 ~（含 ~user 这种写法也按家目录处理）与所有 ${HOME}
    if p.startswith("~"):
        p = home + p[1:]
    return p.replace("${HOME}", home)


def under(root: str, p: str) -> bool:
    return p == root or p.startswith(root + "/")


def _under_any(roots: list[str], p: str) -> bool:
    return any(under(r, p) for r in roots)


def _items(v: Any) -> list[Any]:
    """等价 jq 的 `.[]?`：数组取元素，对象取值，其余（含 null）为空。"""
    if isinstance(v, list):
        return v
    if isinstance(v, dict):
        return list(v.values())
    return []


def _text(v: Any) -> str:
    """等价 `jq -r '.x? // empty'`：null、false 与缺失都变成空串，标量取其文本，复合值取紧凑 JSON。"""
    if v is None or v is False:
        return ""
    if isinstance(v, str):
        return v
    return json.dumps(v, ensure_ascii=False, separators=(",", ":"))


def _get(item: Any, key: str) -> Any:
    return item.get(key) if isinstance(item, dict) else None


def _git(cwd: str, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True)


_IMPORT_TARGET = re.compile(r"^(~/|/)[^/]")
_NETWORK_TARGET = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)?$")
_GRANT = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$")


def resolve_plan(
    cwd: str,
    ceiling_path: str,
    *,
    home: str | None = None,
    yaml_loader: Callable[[str], Any] = load_yaml,
) -> Plan:
    home = home if home is not None else os.environ["HOME"]
    ceiling = yaml_loader(ceiling_path) or {}

    allowed_roots: list[str] = []
    for root in _items(ceiling.get("mount_roots")):
        root = _text(root)
        if not root:
            continue
        expanded = expand_path(root, home)
        if os.path.isdir(expanded):
            allowed_roots.append(os.path.realpath(expanded))

    in_git = _git(cwd, "rev-parse", "--is-inside-work-tree").returncode == 0
    project_root = ""
    if in_git:
        project_root = _git(cwd, "rev-parse", "--show-toplevel").stdout.strip()
    project_root = os.path.realpath(project_root or cwd)

    if not _under_any(allowed_roots, project_root):
        raise PlanError(f"当前项目根目录 {project_root} 超出沙箱能力上限 (未落在 sb.yaml mount_roots 挂载根内)")

    git_common_dir = ""
    if in_git:
        raw = _git(cwd, "rev-parse", "--git-common-dir").stdout.strip()
        if raw:
            git_common_dir = os.path.realpath(os.path.join(cwd, raw))
    if git_common_dir and not under(project_root, git_common_dir) and not _under_any(allowed_roots, git_common_dir):
        raise PlanError(f"worktree 的 git common dir {git_common_dir} 超出沙箱能力上限，请先把该路径加入 mount_roots")

    imports: list[Import] = []
    network: list[str] = []
    paths: list[PathGrant] = []

    proj_cfg = os.path.join(project_root, ".sandbox.yaml")
    if os.path.isfile(proj_cfg):
        cfg = yaml_loader(proj_cfg) or {}
        imports = _resolve_imports(_items(cfg.get("imports")), project_root, home)
        network = _resolve_network(_items(cfg.get("network")))
        paths = _resolve_paths(_items(cfg.get("paths")), project_root, home, allowed_roots)

    grants: list[str] = []
    ceiling_net = ceiling.get("network")
    ceiling_net = ceiling_net if isinstance(ceiling_net, dict) else {}
    for grant in _items(ceiling_net.get("default_grant")):
        grant = _text(grant)
        if not grant:
            continue
        if not _GRANT.match(grant):
            raise PlanError(f"sb.yaml network.default_grant 只接受 IP:端口: {grant}")
        grants.append(grant)
    if grants:
        network = sorted(set(network + grants))

    default_allow = [a for a in _items(ceiling_net.get("allow")) if isinstance(a, str) and a.startswith("host:tcp:")]

    return Plan(
        project_root=project_root,
        git_common_dir=git_common_dir,
        cwd=cwd,
        imports=imports,
        network=network,
        paths=paths,
        default_allow=default_allow,
    )


def _resolve_imports(items: list[Any], project_root: str, home: str) -> list[Import]:
    verified: list[tuple[str, str, str]] = []
    for item in items:
        src, target = _text(_get(item, "src")), _text(_get(item, "target"))
        if not src or not target:
            raise PlanError(
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
            raise PlanError(f"imports 的 target 必须以 ~/ 或 / 开头、不含 ..、位于某个子目录内: {target}")
        src = expand_path(src, home)
        if not src.startswith("/"):
            src = f"{project_root}/{src}"
        if not os.path.isfile(src):
            raise PlanError(f".sandbox.yaml 中声明的导入文件不存在: {src}")
        verified.append((os.path.realpath(src), target, re.sub(r"/[^/]*$", "", target, count=1)))

    seen: set[str] = set()
    for _, target, _ in sorted(verified, key=lambda v: v[1]):
        if target in seen:
            raise PlanError(f"imports 的 target 重复: {target}")
        seen.add(target)

    dirs = sorted({d for _, _, d in verified})
    return [Import(src=s, target=t, dir=d, stage=dirs.index(d)) for s, t, d in verified]


def _resolve_network(items: list[Any]) -> list[str]:
    targets: list[str] = []
    for item in items:
        target = _text(item)
        if not target:
            continue
        if not _NETWORK_TARGET.match(target):
            raise PlanError(f".sandbox.yaml 的 network 只接受 IP 或 IP:端口: {target}")
        targets.append(target)
    return targets


def _resolve_paths(items: list[Any], project_root: str, home: str, allowed_roots: list[str]) -> list[PathGrant]:
    grants: list[PathGrant] = []
    for item in items:
        readonly = False
        if isinstance(item, str):
            if item.endswith(":ro"):
                p, readonly = item.removesuffix(":ro"), True
            else:
                p = item
        else:
            p = _text(_get(item, "path"))
            readonly = _get(item, "readonly") is True or _get(item, "ro") is True
        if p.startswith("~"):
            p = home + p[1:]
        if not p.startswith("/"):
            p = f"{project_root}/{p}"
        if not os.path.exists(p):
            raise PlanError(f".sandbox.yaml 中声明的额外路径不存在: {p}")
        real = os.path.realpath(p)
        if not _under_any(allowed_roots, real):
            raise PlanError(f".sandbox.yaml 中额外路径 {real} 超出能力上限 (未落在 mount_roots 内)")
        grants.append(PathGrant(path=real, readonly=readonly))
    return grants
