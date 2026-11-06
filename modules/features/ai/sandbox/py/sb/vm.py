"""主 VM (sb-main) 的期望配置、能力上限指纹与就绪状态机。

能力上限 = sb.yaml 决定的挂载根、VM 级网络策略、secret 与规格。指纹只含这些，所以改它们要重建 VM，
改发布目录里的声明配置不用。共用 mise 目录的宿主真实路径不进指纹：换机器或搬目录不该重建。
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
import tempfile
from contextlib import contextmanager
from dataclasses import dataclass
from typing import Any, Iterator

from . import sync
from .config import VM_NAME, Config
from .errors import SbError
from .locks import LockTimeout, flock
from .msb import Msb

_MISE_PLACEHOLDER = "__SB_MISE_HOST__"


def log(msg: str) -> None:
    print(msg, file=sys.stderr)


@contextmanager
def lifecycle_lock(cfg: Config, action: str) -> Iterator[None]:
    """主 VM 的生命周期互斥：创建、重建、停止、删除、首次启动都要拿。"""
    path = os.path.join(cfg.lock_dir, "sb-main.lock")
    try:
        with flock(path, 300):
            yield
    except LockTimeout:
        log(f"[-] 错误: 获取生命周期锁超时 (300s): {path}，本次操作放弃")
        raise SbError(f"主 VM {VM_NAME} 生命周期锁被其他进程长期持有，放弃本次{action}") from None


@dataclass(frozen=True)
class Desired:
    """sb.yaml 推出的主 VM 期望配置。conf 里 mise 目录的宿主路径是占位符，指纹因此不随它变。"""

    conf: dict[str, Any]
    volume: str
    volume_size: str
    mise_host_dir: str

    @property
    def fingerprint(self) -> str:
        canon = json.dumps(self.conf, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        return hashlib.sha256((canon + "\n").encode()).hexdigest()

    def msb_conf(self) -> dict[str, Any]:
        mounts = [m.replace(_MISE_PLACEHOLDER, self.mise_host_dir) if isinstance(m, str) else m for m in self.conf["mounts"]]
        return {**self.conf, "mounts": mounts}


def desired(cfg: Config) -> Desired:
    ceiling = cfg.ceiling

    roots: list[str] = []
    for r in ceiling.mount_roots:
        os.makedirs(r, exist_ok=True)
        roots.append(os.path.realpath(r))

    if not os.path.isdir(os.path.join(cfg.publish_dir, "current")):
        raise SbError(f"沙箱配置尚未发布：{cfg.publish_dir}/current 不存在，先执行 just hm")
    if not os.path.isdir(cfg.mise_host_dir):
        raise SbError(f"共用 mise 目录不存在：{cfg.mise_host_dir}，先执行 just hm")

    mounts: list[Any] = [
        {"named": ceiling.volume_name, "target": "/data"},
        "/nix/store:/nix/store:ro,stat-virt=relaxed",
        f"{os.path.realpath(cfg.publish_dir)}:{cfg.guest_config_mount}:ro,stat-virt=relaxed",
        f"{_MISE_PLACEHOLDER}:{cfg.mise_guest_mount}:rw",
        *[f"{r}:{r}" for r in roots],
    ]
    conf: dict[str, Any] = {
        "image": ceiling.image,
        "cpus": ceiling.cpus,
        "memory": ceiling.memory,
        "mounts": mounts,
        "network": ceiling.network,
    }
    if ceiling.secrets:
        conf["secrets"] = ceiling.secrets
    return Desired(conf, ceiling.volume_name, ceiling.volume_size, os.path.realpath(cfg.mise_host_dir))


class BusyQueryError(Exception):
    pass


def count_contexts(cfg: Config, msb: Msb) -> int:
    """主 VM 里正在运行的执行上下文数；VM 没在运行为 0，查不出来抛 BusyQueryError。"""
    if msb.status(VM_NAME) != "Running":
        return 0
    r = msb.capture("exec", VM_NAME, "--", "bash", cfg.launcher, "--check-busy")
    err = r.stderr[:400].replace("\n", " ")
    if r.returncode != 0:
        raise BusyQueryError(f"guest 查询退出码 {r.returncode}" + (f"，stderr: {err}" if err else ""))
    out = "".join(r.stdout.split())
    if not re.fullmatch(r"[0-9]+", out):
        raise BusyQueryError(f"guest 返回非数字输出 [{out}]" + (f"，stderr: {err}" if err else ""))
    return int(out)


def missing_tools(cfg: Config, msb: Msb) -> list[str]:
    r = msb.capture("exec", VM_NAME, "--", "bash", cfg.guest_status)
    if r.returncode != 0:
        raise SbError(f"查询 {VM_NAME} 缺失工具失败 (rc={r.returncode})")
    rows = [line.split("\t") for line in r.stdout.split("\n") if line]
    return [row[1] for row in rows if row[0] == "missing" and len(row) > 1]


def ensure(cfg: Config, msb: Msb) -> None:
    """让主 VM 处于「运行中且能力上限一致」，必要时创建或重建。"""
    with lifecycle_lock(cfg, "启动/重建"):
        _ensure_locked(cfg, msb)


def ensure_running(cfg: Config, msb: Msb) -> None:
    """sb sync 只需要 VM 在运行：不存在就创建，停止就启动，不检查能力上限。"""
    if msb.inspect(VM_NAME) is None:
        log(f"[sb] VM {VM_NAME} 尚未创建，正在自动启动...")
        ensure(cfg, msb)
    elif msb.status(VM_NAME) != "Running":
        log(f"[sb] VM {VM_NAME} 处于停止状态，正在启动...")
        with lifecycle_lock(cfg, "启动"):
            msb.must("start", VM_NAME)
            msb.wait_running(VM_NAME)


def _ensure_locked(cfg: Config, msb: Msb) -> None:
    want = desired(cfg)
    fp = want.fingerprint

    if msb.capture("volume", "inspect", want.volume).returncode != 0:
        log(f"[sb] 数据卷 {want.volume} 不存在，正在创建 (ext4 disk, 大小: {want.volume_size})...")
        msb.must("volume", "create", want.volume, "--kind", "disk", "--size", want.volume_size, to_stderr=True)

    with tempfile.NamedTemporaryFile("w", suffix=".json", prefix=f"sb-{VM_NAME}-", delete=False) as f:
        json.dump(want.msb_conf(), f, ensure_ascii=False, indent=2)
        conf_path = f.name
    try:
        create = ["create", "--name", VM_NAME, "--conf", conf_path, "--label", f"ceiling_fingerprint={fp}"]
        state = msb.inspect(VM_NAME)
        if state is None:
            log(f"[sb] 正在创建主 VM: {VM_NAME} (上限指纹: {fp[:12]})...")
            msb.must(*create, to_stderr=True)
            msb.wait_running(VM_NAME)
            log(f"[sb] 主 VM {VM_NAME} 创建并启动成功")
            log("[sb] 首次创建自动执行 sb sync 补齐工具...")
            if sync.run_locked(cfg, msb, to_stderr=True) != 0:
                log("[sb] 首次工具自动补齐未全部完成 (可稍后通过 sb sync 补齐)")
        elif ((state.get("config") or {}).get("labels") or {}).get("ceiling_fingerprint") == fp:
            if state.get("status") == "Running":
                log(f"[sb] 主 VM {VM_NAME} 正在运行且能力上限一致，复用现有 VM")
            else:
                log(f"[sb] 主 VM {VM_NAME} 已存在但处于停止状态，正在启动...")
                msb.must("start", VM_NAME, to_stderr=True)
                msb.wait_running(VM_NAME)
                log(f"[sb] 主 VM {VM_NAME} 启动成功")
        else:
            try:
                busy = count_contexts(cfg, msb)
            except BusyQueryError as e:
                raise SbError(f"无法确认主 VM {VM_NAME} 是否有上下文在运行，本次不重建。原因: {e}") from None
            if busy > 0:
                raise SbError(f"能力上限已变，主 VM 有 {busy} 个上下文在运行，全部退出后再启动即按新上限重建。")
            log(f"[sb] 检测到能力上限变化且主 VM {VM_NAME} 空闲，正在重建 (保留数据盘 {want.volume})...")
            msb.capture("stop", VM_NAME)
            msb.capture("rm", "--force", VM_NAME)
            msb.must(*create, to_stderr=True)
            msb.wait_running(VM_NAME)
            log(f"[sb] 主 VM {VM_NAME} 重建完成并已启动")
    finally:
        os.unlink(conf_path)


def _first(*values: Any) -> Any:
    return next((v for v in values if v is not None), "-")


def status_report(cfg: Config, msb: Msb) -> str:
    status, cpus, memory, vm_fp, busy = "Not created", "-", "-", "-", "idle"
    state = msb.inspect(VM_NAME)
    if state is not None:
        status = state.get("status") or ""
        res = (state.get("active_config") or {}).get("resources") or {}
        res_cfg = (state.get("config") or {}).get("resources") or {}
        cpus = str(_first(res.get("cpus"), res_cfg.get("cpus")))
        mib = _first(res.get("memory_mib"), res_cfg.get("memory_mib"))
        memory = (f"{mib // 1024}G" if mib % 1024 == 0 else f"{mib}M") if isinstance(mib, int) else str(mib)
        vm_fp = ((state.get("config") or {}).get("labels") or {}).get("ceiling_fingerprint") or "-"
        try:
            n = count_contexts(cfg, msb)
            busy = f"busy ({n})" if n > 0 else "idle"
        except BusyQueryError as e:
            busy = f"unknown ({e})"

    try:
        current_fp = desired(cfg).fingerprint
    except (SbError, OSError):
        current_fp = "-"

    if status == "Not created":
        match = "not_created"
    elif vm_fp != "-" and vm_fp == current_fp:
        match = "consistent"
    else:
        match = "inconsistent"

    if status == "Running":
        missing = ", ".join(missing_tools(cfg, msb)) or "无"
    elif status == "Not created":
        missing = "-"
    else:
        missing = "未知 (VM 未运行)"

    return "\n".join(
        [
            f"VM 名称: {VM_NAME}",
            f"VM 状态: {status}",
            f"VM 规格: cpus={cpus}, memory={memory}",
            f"运行指纹: {vm_fp}",
            f"当前指纹: {current_fp}",
            f"上限一致: {match}",
            f"运行状态: {busy}",
            f"缺失工具: {missing}",
        ]
    )
