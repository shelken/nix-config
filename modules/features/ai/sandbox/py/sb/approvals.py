"""项目 .sandbox.yaml 的批准：按内容哈希记账，注释与排版变化不触发重新批准。"""

from __future__ import annotations

import hashlib
import os
from typing import Literal

from .config import Config
from .plan import Plan
from .yamlio import canonical_json

State = Literal["none", "approved", "unapproved"]

_STATE_TEXT = {
    "approved": "已批准",
    "unapproved": "未批准，确认以上内容后执行 sb trust",
    "none": "无 .sandbox.yaml，不需要批准",
}


def content_hash(sandbox_yaml: str) -> str:
    return hashlib.sha256(canonical_json(sandbox_yaml)).hexdigest()


def state(cfg: Config, project_root: str) -> State:
    path = os.path.join(project_root, ".sandbox.yaml")
    if not os.path.isfile(path):
        return "none"
    return "approved" if os.path.isfile(os.path.join(cfg.approval_dir, content_hash(path))) else "unapproved"


def approve(cfg: Config, project_root: str) -> str:
    h = content_hash(os.path.join(project_root, ".sandbox.yaml"))
    os.makedirs(cfg.approval_dir, exist_ok=True)
    open(os.path.join(cfg.approval_dir, h), "w").close()
    return h


def render(cfg: Config, plan: Plan) -> str:
    """`sb plan` 给人看的授权摘要。ceiling 里的 default_grant 标成「sb.yaml 默认放行」，其余是项目声明。"""
    pr = plan.project_root

    def section(title: str, rows: list[str]) -> list[str]:
        return [title, *(f"  {r}" for r in rows)] if rows else [title, "  无"]

    lines = [f"项目根: {pr}"]
    gcd = plan.git_common_dir
    if gcd and gcd != pr and not gcd.startswith(pr + "/"):
        lines.append(f"git common dir: {gcd}")
    lines += section("额外路径:", [p.path + ("（只读）" if p.readonly else "") for p in plan.paths])
    lines += section("导入文件:", [f"{i.src} → {i.target}" for i in plan.imports])
    lines += section(
        "放行的私网目标:",
        [t + ("（sb.yaml 默认放行）" if t in cfg.ceiling.default_grants else "（项目声明）") for t in plan.network],
    )
    lines += section("放行的宿主端口:", plan.default_allow)
    lines.append(f"批准状态: {_STATE_TEXT[state(cfg, pr)]}")
    return "\n".join(lines)
