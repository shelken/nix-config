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
from contextlib import ExitStack, contextmanager
from typing import Any, Iterator

from . import sync
from .config import VM_NAME, Config, SbError
from .locks import LockTimeout, flock
from .msb import Msb
from .plan import expand_path, load_yaml

_MISE_PLACEHOLDER = "__SB_MISE_HOST__"


def log(msg: str) -> None:
    print(msg, file=sys.stderr)


@contextmanager
def lifecycle_lock(cfg: Config, action: str) -> Iterator[None]:
    """主 VM 的生命周期互斥：创建、重建、停止、删除、首次启动都要拿。"""
    path = os.path.join(cfg.lock_dir, "sb-main.lock")
    stack = ExitStack()
    try:
        stack.enter_context(flock(path, 300))
    except LockTimeout:
        log(f"[-] 错误: 获取生命周期锁超时 (300s): {path}，本次操作放弃")
        raise SbError(f"主 VM {VM_NAME} 生命周期锁被其他进程长期持有，放弃本次{action}") from None
    with stack:
        yield


class Desired:
    """sb.yaml 推出的主 VM 期望配置。"""

    def __init__(self, conf: dict[str, Any], mise_real: str, mise_spec: str, volume: str, volume_size: str):
        self.conf = conf
        self.volume = volume
        self.volume_size = volume_size
        self._mise_real = f"{mise_real}:{mise_spec}"
        self._mise_placeholder = f"{_MISE_PLACEHOLDER}:{mise_spec}"

    @property
    def fingerprint(self) -> str:
        mounts = [self._mise_placeholder if m == self._mise_real else m for m in self.conf["mounts"]]
        canon = json.dumps({**self.conf, "mounts": mounts}, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        return hashlib.sha256((canon + "\n").encode()).hexdigest()


def _or(v: Any, default: Any) -> Any:
    """jq 的 `//`：只有 null 与 false 才换成默认值，0 和空串照用。"""
    return default if v is None or v is False else v


def desired(cfg: Config) -> Desired:
    if not os.path.isfile(cfg.policy_yaml):
        raise SbError(f"找不到全局能力上限配置文件: {cfg.policy_yaml}")
    raw = load_yaml(cfg.policy_yaml) or {}

    roots: list[str] = []
    for r in raw.get("mount_roots") or []:
        if not r:
            continue
        expanded = expand_path(r, cfg.home)
        os.makedirs(expanded, exist_ok=True)
        roots.append(os.path.realpath(expanded))

    volume = raw.get("volume") or {}
    mounts: list[Any] = [{"named": _or(volume.get("name"), "sb-main-data"), "target": "/data"}]
    mounts.append("/nix/store:/nix/store:ro,stat-virt=relaxed")
    if cfg.sandbox_config and os.path.isdir(cfg.sandbox_config):
        published = os.path.realpath(cfg.sandbox_config)
    elif os.path.isdir(os.path.join(cfg.home, ".config/sandbox/current")):
        published = os.path.realpath(os.path.join(cfg.home, ".config/sandbox"))
    else:
        published = ""
    if published:
        mounts.append(f"{published}:/run/sandbox-config:ro,stat-virt=relaxed")

    os.makedirs(cfg.mise_host_dir, exist_ok=True)
    mise_real = os.path.realpath(cfg.mise_host_dir)
    mounts.append(f"{mise_real}:{cfg.mise_mount_spec}")
    mounts += [f"{r}:{r}" for r in roots]

    network = dict(raw.get("network") or {"policy": "public", "allow": ["public", "dns"]})
    network.pop("default_grant", None)
    conf: dict[str, Any] = {
        "image": _or(raw.get("image"), "ubuntu"),
        "cpus": _or(raw.get("cpus"), 4),
        "memory": _or(raw.get("memory"), "8G"),
        "mounts": mounts,
        "network": network,
    }
    if raw.get("secrets"):
        conf["secrets"] = raw["secrets"]
    return Desired(conf, mise_real, cfg.mise_mount_spec, mounts[0]["named"], _or(volume.get("size"), "8G"))


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
    """让主 VM 处于「运行中且能力上限一致」。调用方负责持有生命周期锁。"""
    want = desired(cfg)
    fp = want.fingerprint

    if msb.capture("volume", "inspect", want.volume).returncode != 0:
        log(f"[sb] 数据卷 {want.volume} 不存在，正在创建 (ext4 disk, 大小: {want.volume_size})...")
        msb.must("volume", "create", want.volume, "--kind", "disk", "--size", want.volume_size, to_stderr=True)

    with tempfile.NamedTemporaryFile("w", suffix=".json", prefix=f"sb-{VM_NAME}-", delete=False) as f:
        json.dump(want.conf, f, ensure_ascii=False, indent=2)
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
            if sync.run_locked(cfg, msb, VM_NAME, [], to_stderr=True) != 0:
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


def status_report(cfg: Config, msb: Msb) -> str:
    status, cpus, memory, vm_fp, busy = "Not created", "-", "-", "-", "idle"
    state = msb.inspect(VM_NAME)
    if state is not None:
        status = state.get("status") or ""
        res = (state.get("active_config") or {}).get("resources") or {}
        res_cfg = (state.get("config") or {}).get("resources") or {}
        cpus = str(_or(res.get("cpus"), _or(res_cfg.get("cpus"), "-")))
        mib = _or(res.get("memory_mib"), _or(res_cfg.get("memory_mib"), "-"))
        memory = (f"{mib // 1024}G" if mib % 1024 == 0 else f"{mib}M") if isinstance(mib, int) else str(mib)
        vm_fp = ((state.get("config") or {}).get("labels") or {}).get("ceiling_fingerprint") or "-"
        try:
            n = count_contexts(cfg, msb)
            busy = f"busy ({n})" if n > 0 else "idle"
        except BusyQueryError as e:
            busy = f"unknown ({e})"

    current_fp = "-"
    if os.path.isfile(cfg.policy_yaml):
        try:
            current_fp = desired(cfg).fingerprint
        except (SbError, OSError):
            pass

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
