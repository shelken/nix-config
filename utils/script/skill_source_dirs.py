#!/usr/bin/env python3
"""从各主机配置求出「input → 在用的 skill 目录」，供 renovate_input_diff.py 过滤上游 diff。

- 逐台主机求值 `flake.skillUpstreams.<host>`（禁用 IFD，不构建）；求值失败的主机
  （例如求值期读取私有 secrets 的主机）跳过并输出 GitHub warning
- 上游路径属于哪个 input：用 flake.lock 的 narHash 算出该 input 的 store 路径，不拉取 input
- 输出 JSON：{ "<input>": ["<仓库内目录>", ...] }
"""
import argparse
import json
import subprocess
import sys


def run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True)


def nix_json(args: list[str]):
    result = run(["nix", "eval", "--json", "--option", "allow-import-from-derivation", "false", *args])
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip().splitlines()[-1] if result.stderr.strip() else "nix eval 失败")
    return json.loads(result.stdout)


def input_prefixes(lock: dict) -> dict[str, str]:
    nodes = lock["nodes"]
    prefixes = {}
    for name, ref in nodes["root"]["inputs"].items():
        nar_hash = nodes[ref].get("locked", {}).get("narHash") if isinstance(ref, str) else None
        if not nar_hash:
            continue
        result = run(["nix-store", "--print-fixed-path", "--recursive", "sha256", nar_hash, "source"])
        if result.returncode != 0:
            raise RuntimeError(f"{name}: {result.stderr.strip()}")
        prefixes[name] = result.stdout.strip()
    return prefixes


def group_dirs(upstreams: list[str], prefixes: dict[str, str]) -> dict[str, list[str]]:
    dirs: dict[str, set[str]] = {}
    for upstream in upstreams:
        for name, prefix in prefixes.items():
            if upstream.startswith(f"{prefix}/"):
                dirs.setdefault(name, set()).add(upstream[len(prefix) + 1 :])
                break
    return {name: sorted(paths) for name, paths in sorted(dirs.items())}


def collect_upstreams(flake: str) -> list[str]:
    upstreams: set[str] = set()
    for host in nix_json([f"{flake}#skillUpstreams", "--apply", "builtins.attrNames"]):
        try:
            upstreams.update(nix_json([f"{flake}#skillUpstreams.{host}"]))
        except RuntimeError as error:
            print(f"::warning::{host} 求值失败，已跳过：{error}")
    return sorted(upstreams)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flake", required=True, help="flake ref，例如 . 或 git+file://…?rev=…")
    parser.add_argument("--lock", required=True, help="与该 flake ref 对应的 flake.lock")
    parser.add_argument("--output", required=True, help="输出 JSON 文件")
    args = parser.parse_args()
    with open(args.lock, encoding="utf-8") as file:
        prefixes = input_prefixes(json.load(file))
    try:
        upstreams = collect_upstreams(args.flake)
    except RuntimeError as error:
        print(f"列不出主机：{error}", file=sys.stderr)
        sys.exit(1)
    with open(args.output, "w", encoding="utf-8") as file:
        json.dump(group_dirs(upstreams, prefixes), file, indent=2)


if __name__ == "__main__":
    main()
