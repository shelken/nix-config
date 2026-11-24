#!/usr/bin/env python3
"""按模型上下文窗口回填 pi settings.json 的 compaction.modelOverrides.*.reserveTokens。

pi 的触发条件是「已用 token > 窗口 - reserveTokens」，所以想在窗口用到某个节点时压缩，
就把 reserveTokens 设为「窗口 - 节点」。窗口取自运行中 pi 的 RPC get_available_models，
动态发现的 provider（mp、cpa、zed 等）也在其中，数值是精确的（pi --list-models 是四舍五入）。
"""
import argparse
import copy
import json
import os
import shutil
import subprocess
import sys
import threading
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

COMPACT_AT: list[int] = [250_000]
MIN_RESERVE = 16_384
RPC_TIMEOUT = 60

REPO_ROOT = Path(__file__).resolve().parents[3]
SETTINGS_REL = Path("modules/features/ai/pi/settings.json")
SETTINGS_PATH = REPO_ROOT / SETTINGS_REL
SEC_RUN_ENV = "PI_COMPACTION_IN_SEC_RUN"


def model_key(entry: str) -> str:
    return entry.rsplit(":", 1)[0]


def enabled_model_keys(settings: Mapping[str, Any]) -> list[str]:
    return list(dict.fromkeys(model_key(entry) for entry in settings.get("enabledModels", [])))


def reserve_for(window: int, thresholds: Sequence[int], min_reserve: int) -> int | None:
    usable = [threshold for threshold in thresholds if window - threshold >= min_reserve]
    return window - max(usable) if usable else None


def apply_overrides(
    settings: Mapping[str, Any],
    windows: Mapping[str, int],
    thresholds: Sequence[int],
    min_reserve: int,
) -> tuple[dict[str, Any], list[str]]:
    updated = copy.deepcopy(dict(settings))
    compaction = updated.setdefault("compaction", {})
    previous = compaction.get("modelOverrides", {})
    overrides: dict[str, Any] = {}
    missing: list[str] = []

    for key in enabled_model_keys(settings):
        if key not in windows:
            missing.append(key)
            if key in previous:
                overrides[key] = previous[key]
            continue
        fields = {k: v for k, v in previous.get(key, {}).items() if k != "reserveTokens"}
        reserve = reserve_for(windows[key], thresholds, min_reserve)
        if reserve is not None:
            fields["reserveTokens"] = reserve
        if fields:
            overrides[key] = fields

    compaction["modelOverrides"] = overrides
    return updated, missing


def format_override_diff(before: Mapping[str, Any], after: Mapping[str, Any]) -> list[str]:
    return [
        f"{key}: {before.get(key)} -> {after.get(key)}"
        for key in sorted(set(before) | set(after))
        if before.get(key) != after.get(key)
    ]


def fetch_windows(timeout: int = RPC_TIMEOUT) -> dict[str, int]:
    timed_out = threading.Event()
    request = json.dumps({"id": "models", "type": "get_available_models"}) + "\n"

    with subprocess.Popen(
        ["pi", "--mode", "rpc", "--no-session"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    ) as proc:
        assert proc.stdin is not None and proc.stdout is not None

        def kill_on_timeout() -> None:
            timed_out.set()
            proc.kill()

        timer = threading.Timer(timeout, kill_on_timeout)
        timer.start()
        try:
            try:
                proc.stdin.write(request)
                proc.stdin.flush()
            except BrokenPipeError as exc:
                raise RuntimeError("pi 在接收 RPC 请求前退出") from exc

            for line in proc.stdout:
                try:
                    reply = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if reply.get("id") != "models":
                    continue
                if reply.get("success") is False:
                    raise RuntimeError(f"pi 返回错误: {reply.get('error', reply)}")
                models = reply.get("data", {}).get("models")
                if not isinstance(models, list):
                    raise RuntimeError(f"pi 返回了意外的模型列表结构: {reply}")
                return {f"{m['provider']}/{m['id']}": m["contextWindow"] for m in models}
        finally:
            timer.cancel()
            if proc.poll() is None:
                proc.kill()

    if timed_out.is_set():
        raise RuntimeError(f"等待 pi 返回模型列表超时（>{timeout}s）")
    raise RuntimeError("pi 在返回模型列表前退出")


def read_head_settings() -> dict[str, Any] | None:
    proc = subprocess.run(
        ["git", "show", f"HEAD:{SETTINGS_REL.as_posix()}"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return None
    return json.loads(proc.stdout)


def reexec_in_sec_run() -> None:
    if os.environ.get(SEC_RUN_ENV) or not shutil.which("sec-run"):
        return
    env = {**os.environ, SEC_RUN_ENV: "1"}
    os.execvpe(
        "sec-run",
        ["sec-run", sys.executable, str(Path(__file__).resolve()), "--pre-commit"],
        env,
    )


def sync_settings(current: Mapping[str, Any]) -> bool:
    updated, missing = apply_overrides(current, fetch_windows(), COMPACT_AT, MIN_RESERVE)
    before = current.get("compaction", {}).get("modelOverrides", {})
    after = updated["compaction"]["modelOverrides"]
    for line in format_override_diff(before, after):
        print(line)
    for key in missing:
        print(f"警告: pi 的模型列表里没有 {key}，保持原值", file=sys.stderr)
    if updated == current:
        return False
    SETTINGS_PATH.write_text(json.dumps(updated, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"已写入 {SETTINGS_PATH}")
    return True


def run_pre_commit(current: Mapping[str, Any]) -> int:
    head = read_head_settings()
    if head is None or set(enabled_model_keys(current)) == set(enabled_model_keys(head)):
        return 0
    reexec_in_sec_run()
    if sync_settings(current):
        print("已自动回填 reserveTokens，请检查 diff 并重新 git add 后提交", file=sys.stderr)
        return 1
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--pre-commit", action="store_true", help="仅在 enabledModels 变更时回填")
    args = parser.parse_args(argv)

    current = json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
    if args.pre_commit:
        return run_pre_commit(current)
    if not sync_settings(current):
        print("reserveTokens 已是最新")
    return 0


if __name__ == "__main__":
    sys.exit(main())
