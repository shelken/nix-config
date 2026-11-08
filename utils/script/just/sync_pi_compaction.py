#!/usr/bin/env python3
"""按模型上下文窗口回填 pi settings.json 的 compaction.modelOverrides.*.reserveTokens。

pi 的触发条件是「已用 token > 窗口 - reserveTokens」，所以想在窗口用到某个节点时压缩，
就把 reserveTokens 设为「窗口 - 节点」。窗口取自运行中 pi 的 RPC get_available_models，
动态发现的 provider（mp、cpa、zed 等）也在其中，数值是精确的（pi --list-models 是四舍五入）。
"""
import copy
import json
import subprocess
import sys
import threading
from pathlib import Path

# ---- 可调参数 ----------------------------------------------------------------
# 自动压缩节点（token）：窗口用到该值时压缩。按「向下就近」选：取不超过窗口的最大节点
COMPACT_AT = (250_000, 400_000)
# 节点与窗口之差（即 reserveTokens）的下限；更小的差放弃该节点。压缩摘要自己也要占空间，
# 取 pi 默认的 reserveTokens
MIN_RESERVE = 16_384
# 等 pi 返回模型列表的秒数上限
RPC_TIMEOUT = 60
# ------------------------------------------------------------------------------

SETTINGS = Path(__file__).resolve().parents[3] / "modules/features/ai/pi/settings.json"


def reserve_for(window, nodes, floor):
    """窗口对应的 reserveTokens；没有节点满足下限时返回 None（走 pi 默认）。"""
    usable = [n for n in nodes if window - n >= floor]
    return window - max(usable) if usable else None


def apply(settings, windows, nodes, floor):
    """返回 (新 settings, 查不到窗口的模型)。查不到窗口的模型保持原 override，不凭空改。"""
    result = copy.deepcopy(settings)
    compaction = result.setdefault("compaction", {})
    old = compaction.get("modelOverrides", {})
    new = {}
    missing = []
    for entry in settings["enabledModels"]:
        key = entry.rsplit(":", 1)[0]  # 去掉 :thinking 后缀
        if key not in windows:
            missing.append(key)
            if key in old:
                new[key] = old[key]
            continue
        reserve = reserve_for(windows[key], nodes, floor)
        fields = {k: v for k, v in old.get(key, {}).items() if k != "reserveTokens"}
        if reserve is not None:
            fields["reserveTokens"] = reserve
        if fields:
            new[key] = fields
    compaction["modelOverrides"] = new
    return result, missing


def fetch_windows():
    proc = subprocess.Popen(
        ["pi", "--mode", "rpc", "--no-session"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    timer = threading.Timer(RPC_TIMEOUT, proc.kill)
    timer.start()
    try:
        proc.stdin.write(json.dumps({"id": "models", "type": "get_available_models"}) + "\n")
        proc.stdin.flush()
        for line in proc.stdout:
            try:
                reply = json.loads(line)
            except json.JSONDecodeError:
                continue
            if reply.get("id") == "models":
                return {f"{m['provider']}/{m['id']}": m["contextWindow"] for m in reply["data"]["models"]}
        raise RuntimeError("pi 在返回模型列表前退出或超时")
    finally:
        timer.cancel()
        proc.kill()


def main():
    old = json.loads(SETTINGS.read_text())
    new, missing = apply(old, fetch_windows(), COMPACT_AT, MIN_RESERVE)
    before = old.get("compaction", {}).get("modelOverrides", {})
    after = new["compaction"]["modelOverrides"]
    for key in sorted(set(before) | set(after)):
        if before.get(key) != after.get(key):
            print(f"{key}: {before.get(key)} -> {after.get(key)}")
    for key in missing:
        print(f"警告: pi 的模型列表里没有 {key}，保持原值", file=sys.stderr)
    if new == old:
        print("reserveTokens 已是最新")
        return
    SETTINGS.write_text(json.dumps(new, indent=2, ensure_ascii=False) + "\n")
    print(f"已写入 {SETTINGS}")


if __name__ == "__main__":
    main()
