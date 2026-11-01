import importlib.util
from pathlib import Path

SCRIPT = Path(__file__).with_name("renovate_input_diff.py")
spec = importlib.util.spec_from_file_location("renovate_input_diff", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def node(owner, repo, rev):
    source = {"type": "git", "url": f"https://github.com/{owner}/{repo}", "ref": "main", "rev": rev}
    return {"locked": source, "original": source}


def lock(inputs):
    return {"nodes": {"root": {"inputs": {name: name for name in inputs}}, **inputs}}


skill_source = {"demo-skill": ["skills/demo"]}

base = lock({"demo-skill": node("example", "demo-skill", "a" * 40), "nixpkgs": node("NixOS", "nixpkgs", "b" * 40)})
head = lock(
    {
        "demo-skill": node("example", "demo-skill", "c" * 40),
        "nixpkgs": node("NixOS", "nixpkgs", "b" * 40),
        "added-input": node("example", "added", "d" * 40),
    }
)

# 只有 rev 变化（或新增/移除）的 input 才算变化，未变的 nixpkgs 不进报告
changed = module.changed_inputs(base, head)
assert [name for name, _, _ in changed] == ["added-input", "demo-skill"], changed
assert module.changed_inputs(base, base) == []

calls = []


def compare_request(method, url, token, payload=None):
    calls.append((method, url, token, payload))
    assert method == "GET"
    return {
        "files": [
            {
                "filename": "skills/demo/SKILL.md",
                "status": "modified",
                "additions": 1,
                "deletions": 1,
                "patch": "@@ -1 +1 @@\n-old\n+new",
                "blob_url": "https://example.test/SKILL.md",
            },
            {
                "filename": "skills/other/SKILL.md",
                "status": "modified",
                "additions": 1,
                "deletions": 1,
                "patch": "@@ -1 +1 @@\n-old\n+new",
                "blob_url": "https://example.test/other.md",
            },
            {
                "filename": "README.md",
                "status": "modified",
                "additions": 1,
                "deletions": 0,
                "patch": "+ignored",
                "blob_url": "https://example.test/README.md",
            },
        ]
    }


module.github_json = compare_request
blocks = module.input_blocks("demo-skill", base["nodes"]["demo-skill"], head["nodes"]["demo-skill"], ["skills/demo"], "token")
body = "\n\n".join(blocks)
assert "skills/demo/SKILL.md" in body
assert "skills/other/SKILL.md" not in body
assert "README.md" not in body
assert "https://github.com/example/demo-skill/compare/" in body
assert len(calls) == 1

# 非 skill input：只给 compare 链接，不查文件
calls.clear()
blocks = module.input_blocks("added-input", None, head["nodes"]["added-input"], None, "token")
body = "\n\n".join(blocks)
assert "新增 input" in body
assert calls == []

# URL 变了但 rev 没变（例如 github: 换 git+https:）：说明 rev 未变，也不查文件
retargeted = dict(base["nodes"]["demo-skill"])
retargeted["original"] = {**retargeted["original"], "type": "github", "url": "https://github.com/example/demo-skill"}
body = "\n\n".join(module.input_blocks("demo-skill", base["nodes"]["demo-skill"], retargeted, ["skills/demo"], "token"))
assert "rev 未变" in body
assert calls == []

# 启用目录内没有改动时给出说明，不列文件
calls.clear()


def no_relevant_files(method, url, token, payload=None):
    return {"files": [{"filename": "docs/x.md", "status": "modified", "additions": 1, "deletions": 0}]}


module.github_json = no_relevant_files
body = "\n\n".join(module.input_blocks("demo-skill", base["nodes"]["demo-skill"], head["nodes"]["demo-skill"], ["skills/demo"], "token"))
assert "没有文件改动" in body

# 溢出：评论装不下的部分写进 summary，并带上运行链接
module.github_json = compare_request
header = [module.MARKER, module.TITLE]
many = [f"### `skill-{index}`\n\n" + "x" * 200 for index in range(20)]
comment, summary = module.compose(header, many, comment_limit=1200, summary_limit=100000, run_url="https://run.test/1")
assert len(comment) <= 1200
assert "本次运行" in comment and "https://run.test/1" in comment
assert summary.startswith(module.TITLE)
assert "skill-19" in summary and "skill-19" not in comment
assert module.compose(header, many[:2], comment_limit=1200, run_url=None)[1] == ""

# 评论按 marker 幂等更新：已有自己的评论就 PATCH，否则 POST
requests = []


def paginated_request(method, url, token, payload=None):
    requests.append((method, url, payload))
    if method == "GET" and url.endswith("page=1"):
        return [{"id": index, "user": {"login": "someone"}, "body": "other"} for index in range(100)]
    if method == "GET" and url.endswith("page=2"):
        return [{"id": 9, "user": {"login": "github-actions[bot]"}, "body": module.MARKER}]
    return {}


module.github_json = paginated_request
module.sync_comment("owner/repo", "42", "body", "token")
assert requests[0] == ("GET", "https://api.github.com/repos/owner/repo/issues/42/comments?per_page=100&page=1", None)
assert requests[1] == ("GET", "https://api.github.com/repos/owner/repo/issues/42/comments?per_page=100&page=2", None)
assert requests[-1] == ("PATCH", "https://api.github.com/repos/owner/repo/issues/comments/9", {"body": "body"})

requests = []


def create_request(method, url, token, payload=None):
    requests.append((method, url, payload))
    return [] if method == "GET" else {}


module.github_json = create_request
module.sync_comment("owner/repo", "42", "body", "token")
assert requests == [
    ("GET", "https://api.github.com/repos/owner/repo/issues/42/comments?per_page=100&page=1", None),
    ("POST", "https://api.github.com/repos/owner/repo/issues/42/comments", {"body": "body"}),
]

print("ok")
