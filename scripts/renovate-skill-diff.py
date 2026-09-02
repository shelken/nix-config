#!/usr/bin/env python3
import argparse
import json
import os
import urllib.parse
import urllib.request

MARKER = "<!-- nvfetcher-skill-diff -->"
RELEVANT_PATH_PARTS = ("SKILL.md", "skills/", "references/", "rules/")
MAX_PATCH_LINES = 300
MAX_PATCH_CHARS = 12000
MAX_REPORT_CHARS = 64000


def read_json(path: str) -> dict:
    with open(path, encoding="utf-8") as file:
        return json.load(file)


def source_repository(item: dict) -> tuple[str, str] | None:
    source = item.get("src", {})
    owner = source.get("owner")
    repo = source.get("repo")
    if owner and repo:
        return owner, repo
    url = source.get("url")
    if not url:
        return None
    parts = urllib.parse.urlparse(url).path.strip("/").split("/")
    if len(parts) < 2 or parts[0] == "":
        return None
    return parts[0], parts[1].removesuffix(".git")


def source_revision(item: dict) -> str:
    return item.get("src", {}).get("rev", item.get("version", ""))


def github_json(
    method: str,
    url: str,
    payload: dict | None = None,
    token: str | None = None,
) -> dict | list:
    data = None if payload is None else json.dumps(payload).encode()
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "nvfetcher-skill-diff",
    }
    if data is not None:
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def compare_files(owner: str, repo: str, base: str, head: str, token: str | None) -> list[dict]:
    url = f"https://api.github.com/repos/{owner}/{repo}/compare/{base}...{head}"
    response = github_json("GET", url, token=token)
    if not isinstance(response, dict):
        raise TypeError("GitHub compare response must be an object")
    return response["files"]


def relevant_file(filename: str) -> bool:
    return any(part in filename for part in RELEVANT_PATH_PARTS)


def format_patch(file: dict) -> str:
    patch = file.get("patch", "")
    blob_url = file.get("blob_url", "")
    if not patch:
        return f"_Diff unavailable. [Open file]({blob_url})_\n" if blob_url else "_Diff unavailable._\n"
    lines = patch.splitlines()
    if len(lines) > MAX_PATCH_LINES or len(patch) > MAX_PATCH_CHARS:
        patch = "\n".join(lines[:MAX_PATCH_LINES])
        suffix = f" [Open full file]({blob_url})" if blob_url else ""
        return f"```diff\n{patch}\n```\n\n_Diff truncated.{suffix}_\n"
    return f"```diff\n{patch}\n```\n"


def generate_report(base_data: dict, head_data: dict, source: str, fetch_compare) -> str:
    before = base_data.get(source)
    after = head_data.get(source)
    if before == after:
        return ""

    sections = [MARKER, "## 📦 External Source & Skill Diff Report"]
    if before is None:
        sections.append(f"### `{source}` added at `{after['version']}`")
        return "\n\n".join(sections)
    if after is None:
        sections.append(f"### `{source}` removed from `{before['version']}`")
        return "\n\n".join(sections)

    old_version = before.get("version", "")
    new_version = after.get("version", "")
    sections.append(f"### `{source}`: `{old_version}` → `{new_version}`")
    repository = source_repository(after) or source_repository(before)
    old_revision = source_revision(before)
    new_revision = source_revision(after)
    if repository is None or old_revision == new_revision or not old_revision or not new_revision:
        return "\n\n".join(sections)

    owner, repo = repository
    sections.append(
        f"🔗 [Full GitHub Comparison](https://github.com/{owner}/{repo}/compare/{old_revision}...{new_revision})"
    )
    files = fetch_compare(owner, repo, old_revision, new_revision)
    relevant_files = [file for file in files if relevant_file(file.get("filename", ""))]
    if not relevant_files:
        sections.append("_No changes in `SKILL.md`, `skills/`, `references/`, or `rules/`._")
        return "\n\n".join(sections)

    sections.append("#### 📝 Detailed Skill & Rule Diffs")
    omitted = 0
    for index, file in enumerate(relevant_files):
        filename = file.get("filename", "unknown")
        status = file.get("status", "modified")
        additions = file.get("additions", 0)
        deletions = file.get("deletions", 0)
        section = (
            f"<details><summary><b><code>{filename}</code></b> ({status}, +{additions}, -{deletions})</summary>\n"
            f"{format_patch(file)}</details>"
        )
        projected = "\n\n".join([*sections, section])
        if len(projected) > MAX_REPORT_CHARS - 200:
            omitted = len(relevant_files) - index
            break
        sections.append(section)
    if omitted:
        sections.append(f"_{omitted} additional skill/rule file diffs omitted. Use the comparison link above._")
    return "\n\n".join(sections)


def sync_comment(repository: str, pull_request: str, body: str, request) -> str:
    for page in range(1, 101):
        comments = request(
            "GET",
            f"/repos/{repository}/issues/{pull_request}/comments?per_page=100&page={page}",
            None,
        )
        for comment in comments:
            if comment["user"]["login"] == "github-actions[bot]" and MARKER in comment["body"]:
                request("PATCH", f"/repos/{repository}/issues/comments/{comment['id']}", {"body": body})
                return "updated"
        if len(comments) < 100:
            break
    request("POST", f"/repos/{repository}/issues/{pull_request}/comments", {"body": body})
    return "created"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-file", required=True)
    parser.add_argument("--head-file", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--pull-request", required=True)
    args = parser.parse_args()

    token = os.environ["GITHUB_TOKEN"]
    repository = os.environ["GITHUB_REPOSITORY"]
    report = generate_report(
        read_json(args.base_file),
        read_json(args.head_file),
        args.source,
        lambda owner, repo, base, head: compare_files(owner, repo, base, head, token),
    )
    if not report:
        return

    def request(method: str, path: str, payload: dict | None) -> dict | list:
        return github_json(method, f"https://api.github.com{path}", payload, token)

    print(sync_comment(repository, args.pull_request, report, request))


if __name__ == "__main__":
    main()
