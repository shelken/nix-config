#!/usr/bin/env python3
import argparse
import json
import os
import sys
import urllib.parse
import urllib.request

MARKER = "<!-- renovate-skill-diff -->"
RELEVANT_PATH_PARTS = ("SKILL.md", "skills/", "references/", "rules/")
MAX_PATCH_LINES = 120
MAX_PATCH_CHARS = 6000
MAX_REPORT_CHARS = 60000


def read_json(path: str) -> dict:
    with open(path, encoding="utf-8") as file:
        return json.load(file)


def github_json(method: str, url: str, token: str, payload: dict | None = None) -> dict | list:
    data = None if payload is None else json.dumps(payload).encode()
    headers = {"Accept": "application/vnd.github+json", "Authorization": f"Bearer {token}"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    with urllib.request.urlopen(urllib.request.Request(url, data=data, headers=headers, method=method), timeout=20) as response:
        return json.load(response)


def repository(source: dict) -> tuple[str, str] | None:
    src = source["src"]
    if src.get("owner") and src.get("repo"):
        return src["owner"], src["repo"]
    url = src.get("url")
    if not url:
        return None
    parts = urllib.parse.urlparse(url).path.strip("/").split("/")
    if len(parts) < 2:
        return None
    return parts[0], parts[1].removesuffix(".git")


def report(base: dict, head: dict, source_name: str, token: str) -> str:
    before = base.get(source_name)
    after = head.get(source_name)
    if before == after:
        return ""
    sections = [MARKER, "## 📦 External Source & Skill Diff Report"]
    if before is None:
        sections.append(f"### `{source_name}` added at `{after['version']}`")
        return "\n\n".join(sections)
    if after is None:
        sections.append(f"### `{source_name}` removed from `{before['version']}`")
        return "\n\n".join(sections)

    old_revision = before["src"].get("rev", before["version"])
    new_revision = after["src"].get("rev", after["version"])
    sections.append(f"### `{source_name}`: `{before['version']}` → `{after['version']}`")
    source_repo = repository(after) or repository(before)
    if source_repo is None or old_revision == new_revision:
        return "\n\n".join(sections)
    owner, repo = source_repo
    compare_url = f"https://github.com/{owner}/{repo}/compare/{old_revision}...{new_revision}"
    sections.append(f"🔗 [Full GitHub Comparison]({compare_url})")
    comparison = github_json("GET", f"https://api.github.com/repos/{owner}/{repo}/compare/{old_revision}...{new_revision}", token)
    if not isinstance(comparison, dict):
        raise TypeError("GitHub compare response must be an object")
    files = [file for file in comparison["files"] if any(part in file["filename"] for part in RELEVANT_PATH_PARTS)]
    if not files:
        sections.append("_No changes in `SKILL.md`, `skills/`, `references/`, or `rules/`._")
        return "\n\n".join(sections)

    sections.append("#### 📝 Detailed Skill & Rule Diffs")
    for index, file in enumerate(files):
        patch = file.get("patch", "")
        lines = patch.splitlines()
        if len(lines) > MAX_PATCH_LINES or len(patch) > MAX_PATCH_CHARS:
            patch = "\n".join(lines[:MAX_PATCH_LINES])
            suffix = f"\n\n_Diff truncated. [Open full file]({file['blob_url']})._"
        else:
            suffix = ""
        section = (
            f"<details><summary><b><code>{file['filename']}</code></b> ({file['status']}, +{file['additions']}, -{file['deletions']})</summary>\n\n"
            f"```diff\n{patch}\n```{suffix}\n</details>"
        )
        if len("\n\n".join([*sections, section])) > MAX_REPORT_CHARS - 160:
            sections.append(f"_{len(files) - index} additional skill/rule file diffs omitted. Use the comparison link above._")
            break
        sections.append(section)
    return "\n\n".join(sections)


def sync_comment(repository_name: str, pull_request: str, body: str, token: str) -> None:
    page = 1
    while True:
        comments = github_json(
            "GET",
            f"https://api.github.com/repos/{repository_name}/issues/{pull_request}/comments?per_page=100&page={page}",
            token,
        )
        if not isinstance(comments, list):
            raise TypeError("GitHub comments response must be an array")
        for comment in comments:
            if comment["user"]["login"] == "github-actions[bot]" and MARKER in comment["body"]:
                github_json("PATCH", f"https://api.github.com/repos/{repository_name}/issues/comments/{comment['id']}", token, {"body": body})
                return
        if len(comments) < 100:
            break
        page += 1
    github_json("POST", f"https://api.github.com/repos/{repository_name}/issues/{pull_request}/comments", token, {"body": body})


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-file", required=True)
    parser.add_argument("--head-file", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--pull-request", required=True)
    args = parser.parse_args()
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if not token:
        print("缺少 GitHub token，请设置 GITHUB_TOKEN 或 GH_TOKEN", file=sys.stderr)
        raise SystemExit(1)
    body = report(read_json(args.base_file), read_json(args.head_file), args.source, token)
    if body:
        sync_comment(os.environ["GITHUB_REPOSITORY"], args.pull_request, body, token)


if __name__ == "__main__":
    main()
