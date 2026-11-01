#!/usr/bin/env python3
"""对比 base / head 的 flake.lock，把变化的 input 渲染成一条 PR 评论。

- 每个变化的 input 一段；skill 类静态资源只内联「已启用目录」里的文件改动，
  目录集合由 `nix eval --json .#skillSourceDirs` 生成（单一事实来源见 _skill-sources.nix）
- 非 skill input 只给 GitHub compare 链接
- 全部内容超过 GitHub 评论上限时，溢出部分交给 Job Summary，评论里给出运行链接
"""
import argparse
import json
import os
import sys
import urllib.parse
import urllib.request

MARKER = "<!-- renovate-input-diff -->"
COMMENT_LIMIT = 60000
SUMMARY_LIMIT = 900000
NOTE_RESERVE = 400
COMPARE_FILE_LIMIT = 300
TITLE = "## 📦 flake.lock 变更"

DRY_RUN = False


def read_json(path: str) -> dict:
    with open(path, encoding="utf-8") as file:
        return json.load(file)


def log(message: str) -> None:
    print(message, file=sys.stderr)


def github_json(method: str, url: str, token: str, payload: dict | None = None) -> dict | list:
    log(f"{method} {url}" + (" (dry-run，只打印)" if DRY_RUN and method != "GET" else ""))
    if DRY_RUN and method != "GET":
        return {}
    data = None if payload is None else json.dumps(payload).encode()
    headers = {"Accept": "application/vnd.github+json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if data is not None:
        headers["Content-Type"] = "application/json"
    with urllib.request.urlopen(urllib.request.Request(url, data=data, headers=headers, method=method), timeout=30) as response:
        return json.load(response)


def inputs_of(lock: dict) -> dict:
    nodes = lock.get("nodes", {})
    result = {}
    for name, ref in (nodes.get("root", {}).get("inputs") or {}).items():
        node_name = ref[0] if isinstance(ref, list) and ref else ref
        node = nodes.get(node_name) if isinstance(node_name, str) else None
        if node is not None:
            result[name] = node
    return result


def rev_of(node: dict | None) -> str | None:
    return (node or {}).get("locked", {}).get("rev")


def source_of(node: dict | None) -> str | None:
    node = node or {}
    for attrs in (node.get("locked") or {}, node.get("original") or {}):
        owner, repo = attrs.get("owner"), attrs.get("repo")
        if owner and repo:
            return f"{owner}/{repo}"
    url = (node.get("locked") or {}).get("url") or (node.get("original") or {}).get("url") or ""
    if "://" not in url:
        return None
    parts = [part for part in urllib.parse.urlparse(url).path.strip("/").split("/") if part]
    if len(parts) < 2:
        return None
    return f"{parts[0]}/{parts[1].removesuffix('.git')}"


def changed_inputs(base_lock: dict, head_lock: dict) -> list[tuple[str, dict | None, dict | None]]:
    before, after = inputs_of(base_lock), inputs_of(head_lock)
    return [
        (name, before.get(name), after.get(name))
        for name in sorted(set(before) | set(after))
        if before.get(name) is None or after.get(name) is None or before[name] != after[name]
    ]


def short(rev: str | None) -> str:
    return rev[:7] if rev else "?"


def in_dirs(path: str, dirs: list[str]) -> bool:
    return any(path == directory or path.startswith(f"{directory}/") for directory in dirs)


def render_file(file: dict) -> str:
    summary = (
        f"<b><code>{file['filename']}</code></b> ({file['status']}, +{file['additions']}, -{file['deletions']})"
    )
    patch = file.get("patch")
    if patch is None:
        return f"<details><summary>{summary}</summary>\n\n_diff 过大，GitHub 未返回内容：[查看文件]({file['blob_url']})_\n\n</details>"
    return f"<details><summary>{summary}</summary>\n\n```diff\n{patch.rstrip()}\n```\n\n</details>"


def input_blocks(
    name: str, before: dict | None, after: dict | None, dirs: list[str] | None, token: str
) -> list[str]:
    before_rev, after_rev = rev_of(before), rev_of(after)
    repo = source_of(after or before)
    lines = [f"### `{name}`"]
    if before is None:
        lines.append(f"新增 input，锁定 `{short(after_rev)}`")
    elif after is None:
        lines.append(f"移除 input，原锁定 `{short(before_rev)}`")
    elif before_rev == after_rev:
        lines.append(f"input 定义变了，rev 未变（`{short(after_rev)}`）")
    else:
        lines.append(f"`{short(before_rev)}` → `{short(after_rev)}`")
    if repo and before_rev and after_rev and before_rev != after_rev:
        lines.append(f"🔗 [完整对比](https://github.com/{repo}/compare/{before_rev}...{after_rev})")
    blocks = ["\n".join(lines)]
    if not dirs or not repo or not before_rev or not after_rev or before_rev == after_rev:
        return blocks
    comparison = github_json(
        "GET", f"https://api.github.com/repos/{repo}/compare/{before_rev}...{after_rev}", token
    )
    if not isinstance(comparison, dict):
        raise TypeError("GitHub compare response must be an object")
    all_files = comparison.get("files", [])
    files = [file for file in all_files if in_dirs(file["filename"], dirs)]
    if not files:
        blocks.append(f"_已启用的 skill 目录（{len(dirs)} 个）内没有文件改动。_")
        return blocks
    blocks.append(f"#### 已启用目录内的改动：{len(files)} 个文件")
    blocks.extend(render_file(file) for file in files)
    if len(all_files) >= COMPARE_FILE_LIMIT:
        blocks.append("_GitHub compare 最多返回 300 个文件，其余见上方完整对比。_")
    return blocks


def compose(
    header: list[str],
    blocks: list[str],
    comment_limit: int = COMMENT_LIMIT,
    summary_limit: int = SUMMARY_LIMIT,
    run_url: str | None = None,
) -> tuple[str, str]:
    body = list(header)
    overflow = []
    for block in blocks:
        if len("\n\n".join([*body, block])) <= comment_limit - NOTE_RESERVE:
            body.append(block)
        else:
            overflow.append(block)
    if not overflow:
        return "\n\n".join(body), ""
    link = f"：[本次运行]({run_url})" if run_url else ""
    body.append(f"_评论长度受限，另有 {len(overflow)} 段 diff 见 Job Summary{link}。_")
    summary = "\n\n".join([f"{TITLE}（评论溢出的部分）", *overflow])
    if len(summary) > summary_limit:
        summary = f"{summary[:summary_limit]}\n\n_（Job Summary 超长，已截断：完整内容见 compare 链接）_"
    return "\n\n".join(body), summary


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
                github_json(
                    "PATCH",
                    f"https://api.github.com/repos/{repository_name}/issues/comments/{comment['id']}",
                    token,
                    {"body": body},
                )
                return
        if len(comments) < 100:
            break
        page += 1
    github_json(
        "POST",
        f"https://api.github.com/repos/{repository_name}/issues/{pull_request}/comments",
        token,
        {"body": body},
    )


def main() -> None:
    global DRY_RUN
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-lock", required=True, help="base 一侧的 flake.lock")
    parser.add_argument("--head-lock", required=True, help="head 一侧的 flake.lock")
    parser.add_argument("--skill-dirs", required=True, help="flake.skillSourceDirs 的 JSON：input → 启用的 skill 目录")
    parser.add_argument("--pull-request", help="PR 号；给了才会更新评论")
    parser.add_argument("--summary", help="溢出内容写到这个文件（CI 传 $GITHUB_STEP_SUMMARY）")
    parser.add_argument("--run-url", help="运行链接，溢出时写进评论")
    parser.add_argument("--dry-run", action="store_true", help="只打印写请求，不发/改评论（GET compare 照常执行）")
    parser.add_argument("--print-body", action="store_true", help="把评论正文写到 stdout")
    args = parser.parse_args()
    DRY_RUN = args.dry_run
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN") or ""

    skill_dirs = read_json(args.skill_dirs)
    changed = changed_inputs(read_json(args.base_lock), read_json(args.head_lock))
    if not changed:
        log("flake.lock 里没有 input 变化，不更新评论")
        return
    blocks = []
    for name, before, after in changed:
        blocks.extend(input_blocks(name, before, after, skill_dirs.get(name), token))
    header = [MARKER, TITLE]
    comment, summary = compose(header, blocks, run_url=args.run_url)
    if args.print_body:
        print(comment)
    if args.summary and summary:
        with open(args.summary, "a", encoding="utf-8") as file:
            file.write(f"{summary}\n")
    if args.pull_request:
        sync_comment(os.environ["GITHUB_REPOSITORY"], args.pull_request, comment, token)


if __name__ == "__main__":
    main()
