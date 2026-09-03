#!/usr/bin/env python3
"""按源逐一运行 nvfetcher，为每个有上游更新的源创建独立分支、PR 与 diff 评论。

sync 模式面向 CI：要求干净工作区与 origin/main 引用，使用 gh 与 GitHub API。
dry-run 模式把 nvfetcher 输出到临时目录，只报告更新状态，不改动仓库任何文件。
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "nvfetcher.toml"
GENERATED_JSON = ROOT / "_sources" / "generated.json"
BRANCH_PREFIX = "automation/nvfetcher/"
COMMITTER_NAME = "github-actions[bot]"
COMMITTER_EMAIL = "41898282+github-actions[bot]@users.noreply.github.com"
DIFF_SCRIPT = ROOT / "scripts" / "renovate-skill-diff.py"


def run(*args: str) -> None:
    subprocess.run(args, check=True, cwd=ROOT)


def output(*args: str) -> str:
    return subprocess.run(args, check=True, capture_output=True, text=True, cwd=ROOT).stdout.strip()


def sources_from(config: Path) -> list[str]:
    return list(tomllib.loads(config.read_text()))


def changed_sources(baseline: dict, head: dict, source: str) -> list[str]:
    changed = sorted(name for name in set(baseline) | set(head) if baseline.get(name) != head.get(name))
    if changed != [source]:
        raise ValueError(f"nvfetcher 单源过滤失效，期望只更新 {source}，实际变更：{changed}")
    return changed


def nvfetcher_run(config: Path, source: str, output_dir: Path) -> None:
    subprocess.run(
        ["nvfetcher", "-c", str(config), "-f", f"^{source}$", "-o", str(output_dir)],
        check=True, cwd=ROOT,
    )


def remote_branch_exists(branch: str) -> bool:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-remote", "--exit-code", "--heads", "origin", branch],
        capture_output=True,
    )
    return result.returncode == 0


def gh_pr_number(branch: str) -> str:
    repository = os.environ["GITHUB_REPOSITORY"]
    return output(
        "gh", "pr", "list", "--repo", repository, "--head", branch, "--state", "open",
        "--json", "number", "--jq", ".[0].number // empty",
    )


def create_pull_request(branch: str, source: str) -> str:
    repository = os.environ["GITHUB_REPOSITORY"]
    return output(
        "gh", "pr", "create", "--repo", repository, "--base", "main",
        "--head", branch, "--title", f"chore(nvfetcher): update {source}",
        "--body", f"Automated update of `{source}` via nvfetcher.",
        "--json", "number", "--jq", ".number",
    )


def sync_comment(base_file: str, head_file: str, source: str, pull_request: str) -> None:
    subprocess.run(
        ["python3", str(DIFF_SCRIPT), "--base-file", base_file, "--head-file", head_file,
         "--source", source, "--pull-request", pull_request],
        check=True, env=dict(os.environ),
    )


def sync_source(source: str, config: Path, original_branch: str, baseline_json: str) -> None:
    run("git", "restore", "--source=HEAD", "--", "_sources/generated.json", "_sources/generated.nix")
    nvfetcher_run(config, source, ROOT / "_sources")
    head_json = GENERATED_JSON.read_text()
    baseline = json.loads(baseline_json)
    head = json.loads(head_json)
    if baseline.get(source) == head.get(source):
        print(f"[{source}] up to date")
        return
    changed_sources(baseline, head, source)
    before_version = baseline.get(source, {}).get("version", "(new)")
    after_version = head[source]["version"]

    branch = f"{BRANCH_PREFIX}{source}"
    run("git", "switch", "-C", branch, "origin/main")
    run("git", "add", "--", "_sources/generated.json", "_sources/generated.nix")
    run("git", "-c", f"user.name={COMMITTER_NAME}", "-c", f"user.email={COMMITTER_EMAIL}",
        "commit", "-m", f"chore(nvfetcher): update {source}")
    if remote_branch_exists(branch):
        run("git", "push", "--force", "origin", f"HEAD:{branch}")
    else:
        run("git", "push", "-u", "origin", f"HEAD:{branch}")
    pull_request = gh_pr_number(branch) or create_pull_request(branch, source)
    with tempfile.NamedTemporaryFile("w", suffix=".json") as base_tmp, tempfile.NamedTemporaryFile("w", suffix=".json") as head_tmp:
        base_tmp.write(baseline_json)
        head_tmp.write(head_json)
        base_tmp.flush()
        head_tmp.flush()
        sync_comment(base_tmp.name, head_tmp.name, source, pull_request)
    print(f"[{source}] updated {before_version} -> {after_version} via PR #{pull_request}")
    run("git", "switch", original_branch)
    run("git", "restore", "--source=HEAD", "--", "_sources/generated.json", "_sources/generated.nix")


def check_source(source: str, config: Path, baseline_json: str) -> bool:
    baseline = json.loads(baseline_json)
    with tempfile.TemporaryDirectory() as tmp:
        output_dir = Path(tmp)
        shutil.copy(ROOT / "_sources" / "generated.json", output_dir / "generated.json")
        shutil.copy(ROOT / "_sources" / "generated.nix", output_dir / "generated.nix")
        nvfetcher_run(config, source, output_dir)
        head = json.loads((output_dir / "generated.json").read_text())
    if baseline.get(source) == head.get(source):
        print(f"[{source}] up to date")
        return False
    changed_sources(baseline, head, source)
    before_version = baseline.get(source, {}).get("version", "(new)")
    after_version = head[source]["version"]
    print(f"[{source}] would update {before_version} -> {after_version}")
    return True


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=CONFIG, help="nvfetcher 配置文件")
    parser.add_argument("--sources", help="逗号分隔的源名列表，缺省处理配置中全部源")
    parser.add_argument("--dry-run", action="store_true", help="只报告更新状态，不改动 git 与仓库文件")
    args = parser.parse_args()
    config = args.config if args.config.is_absolute() else ROOT / args.config
    sources = args.sources.split(",") if args.sources else sources_from(config)
    baseline_json = GENERATED_JSON.read_text()

    if args.dry_run:
        for source in sources:
            check_source(source, config, baseline_json)
        return

    original_branch = output("git", "branch", "--show-current")
    if not original_branch:
        print("sync 模式需要处于具名分支（CI 中为 main）", file=sys.stderr)
        raise SystemExit(1)
    if output("git", "status", "--porcelain"):
        print("工作区不干净，拒绝运行", file=sys.stderr)
        raise SystemExit(1)
    failures = []
    for source in sources:
        try:
            sync_source(source, config, original_branch, baseline_json)
        except subprocess.CalledProcessError as error:
            failures.append(f"{source}: {error}")
            run("git", "switch", original_branch)
            run("git", "restore", "--source=HEAD", "--", "_sources/generated.json", "_sources/generated.nix")
    if failures:
        print("以下源处理失败：", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
