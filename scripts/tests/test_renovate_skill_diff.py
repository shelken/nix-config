import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("renovate_skill_diff", Path("scripts/renovate-skill-diff.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

base = {
    "demo-skill": {
        "version": "v1.0.0",
        "src": {"owner": "example", "repo": "demo-skill", "rev": "v1.0.0"},
    },
    "other-skill": {
        "version": "v2.0.0",
        "src": {"owner": "example", "repo": "other-skill", "rev": "v2.0.0"},
    },
}
head = {
    "demo-skill": {
        "version": "v1.1.0",
        "src": {"owner": "example", "repo": "demo-skill", "rev": "v1.1.0"},
    },
    "other-skill": {
        "version": "v2.1.0",
        "src": {"owner": "example", "repo": "other-skill", "rev": "v2.1.0"},
    },
}
report = module.generate_report(
    base,
    head,
    "demo-skill",
    lambda owner, repo, old, new: [
        {
            "filename": "skills/demo/SKILL.md",
            "status": "modified",
            "additions": 1,
            "deletions": 1,
            "patch": "@@ -1 +1 @@\n-old\n+new",
            "blob_url": "https://example.test/SKILL.md",
        }
    ],
)
assert module.MARKER in report
assert "`demo-skill`: `v1.0.0` → `v1.1.0`" in report
assert "https://github.com/example/demo-skill/compare/v1.0.0...v1.1.0" in report
assert "skills/demo/SKILL.md" in report
assert "other-skill" not in report
assert module.generate_report(base, base, "demo-skill", lambda *_: []) == ""

requests = []


def request(method, path, payload):
    requests.append((method, path, payload))
    if method == "GET":
        return []
    return {}


assert module.sync_comment("owner/repo", "42", report, request) == "created"
assert requests[-1] == ("POST", "/repos/owner/repo/issues/42/comments", {"body": report})

requests = []


def request(method, path, payload):
    requests.append((method, path, payload))
    if path.endswith("page=1"):
        return [{"id": index, "user": {"login": "someone"}, "body": "other"} for index in range(100)]
    if path.endswith("page=2"):
        return [{"id": 9, "user": {"login": "github-actions[bot]"}, "body": module.MARKER}]
    return {}


assert module.sync_comment("owner/repo", "42", report, request) == "updated"
assert requests[0] == ("GET", "/repos/owner/repo/issues/42/comments?per_page=100&page=1", None)
assert requests[1] == ("GET", "/repos/owner/repo/issues/42/comments?per_page=100&page=2", None)
assert requests[-1] == ("PATCH", "/repos/owner/repo/issues/comments/9", {"body": report})
