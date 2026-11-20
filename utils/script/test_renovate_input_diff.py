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

blocks = module.input_blocks("added-input", None, head["nodes"]["added-input"], None, "token")
assert "新增 input" in "\n\n".join(blocks)

calls.clear()
retargeted = dict(base["nodes"]["demo-skill"])
retargeted["original"] = {**retargeted["original"], "type": "github", "url": "https://github.com/example/demo-skill"}
body = "\n\n".join(module.input_blocks("demo-skill", base["nodes"]["demo-skill"], retargeted, ["skills/demo"], "token"))
assert "rev 未变" in body
assert calls == []

calls.clear()


def no_relevant_files(method, url, token, payload=None):
    return {"files": [{"filename": "docs/x.md", "status": "modified", "additions": 1, "deletions": 0}]}


module.github_json = no_relevant_files
body = "\n\n".join(module.input_blocks("demo-skill", base["nodes"]["demo-skill"], head["nodes"]["demo-skill"], ["skills/demo"], "token"))
assert "没有文件改动" in body

module.github_json = compare_request
header = [module.MARKER, module.TITLE]
many = [f"### `skill-{index}`\n\n" + "x" * 200 for index in range(20)]
comment, summary = module.compose(header, many, comment_limit=1200, summary_limit=100000, run_url="https://run.test/1")
assert len(comment) <= 1200
assert "本次运行" in comment and "https://run.test/1" in comment
assert summary.startswith(module.TITLE)
assert "skill-19" in summary and "skill-19" not in comment
assert module.compose(header, many[:2], comment_limit=1200, run_url=None)[1] == ""

base_dirs = {"demo-skill": ["skills/demo", "skills/gone"]}
head_dirs = {"demo-skill": ["skills/demo"]}
assert module.skill_dirs_for("demo-skill", base_dirs, head_dirs) == ["skills/demo", "skills/gone"]


def deleted_skill(method, url, token, payload=None):
    return {
        "files": [
            {
                "filename": "skills/gone/SKILL.md",
                "status": "removed",
                "additions": 0,
                "deletions": 12,
                "patch": "@@ -1,12 +0,0 @@\n-x",
                "blob_url": "https://example.test/gone.md",
            }
        ]
    }


module.github_json = deleted_skill
body = "\n\n".join(
    module.input_blocks(
        "demo-skill",
        base["nodes"]["demo-skill"],
        head["nodes"]["demo-skill"],
        module.skill_dirs_for("demo-skill", base_dirs, head_dirs),
        "token",
    )
)
assert "skills/gone/SKILL.md" in body

renamed_file = {
    "filename": "cursor-team-kit/skills/control-ui/references/example.md",
    "previous_filename": "cursor-team-kit/skills/control-cli/references/example.md",
    "status": "renamed",
    "additions": 0,
    "deletions": 0,
    "patch": "",
    "blob_url": "https://example.test/moved.md",
}
assert module.matches_dirs(renamed_file, ["cursor-team-kit/skills/control-cli"])
assert not module.matches_dirs(renamed_file, ["cursor-team-kit/skills/other"])
module.github_json = lambda *args, **kwargs: {"files": [renamed_file]}
body = "\n\n".join(
    module.input_blocks(
        "demo-skill",
        base["nodes"]["demo-skill"],
        head["nodes"]["demo-skill"],
        ["cursor-team-kit/skills/control-cli"],
        "token",
    )
)
assert "control-ui/references/example.md" in body


def three_hundred_files(method, url, token, payload=None):
    return {
        "files": [
            {
                "filename": f"docs/{index}.md",
                "status": "modified",
                "additions": 1,
                "deletions": 0,
                "patch": "+x",
                "blob_url": "https://example.test/x.md",
            }
            for index in range(module.COMPARE_FILE_LIMIT)
        ]
    }


module.github_json = three_hundred_files
body = "\n\n".join(module.input_blocks("demo-skill", base["nodes"]["demo-skill"], head["nodes"]["demo-skill"], ["skills/demo"], "token"))
assert "结果不完整" in body
assert "没有文件改动" not in body

cjk = [f"### `中文{index}`\n\n" + "汉" * 200 for index in range(20)]
_, summary = module.compose(header, cjk, comment_limit=1000, summary_limit=1200, run_url=None)
assert summary.endswith(module.SUMMARY_TRUNCATION_NOTE)
assert len(summary.encode("utf-8")) <= 1200
tiny = module.compose(header, cjk, comment_limit=1000, summary_limit=40, run_url=None)[1]
assert len(tiny.encode("utf-8")) <= 40

assert module.fence_for("a\n```\nb") == "````"
assert module.fence_for("x\n```````\ny") == "````````"
rendered = module.render_file(
    {
        "filename": 'skills/demo/<b>&"x".md',
        "status": "modified",
        "additions": 1,
        "deletions": 1,
        "patch": "```\n-old\n+new",
        "blob_url": "https://example.test/x.md",
    }
)
assert "<code>skills/demo/&lt;b&gt;&amp;&quot;x&quot;.md</code>" in rendered
assert "````diff" in rendered

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
