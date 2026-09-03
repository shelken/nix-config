import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("renovate_skill_diff", ROOT / "scripts/renovate-skill-diff.py")
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

calls = []


def compare_request(method, url, token, payload=None):
    calls.append((method, url, token, payload))
    assert method == "GET"
    assert url == "https://api.github.com/repos/example/demo-skill/compare/v1.0.0...v1.1.0"
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
body = module.report(base, head, "demo-skill", "token")
assert module.MARKER in body
assert "`demo-skill`: `v1.0.0` → `v1.1.0`" in body
assert "https://github.com/example/demo-skill/compare/v1.0.0...v1.1.0" in body
assert "skills/demo/SKILL.md" in body
assert "README.md" not in body
assert "other-skill" not in body
assert len(calls) == 1
assert module.report(base, base, "demo-skill", "token") == ""


def failed_compare(*_args, **_kwargs):
    raise RuntimeError("GitHub compare failed")


module.github_json = failed_compare
try:
    module.report(base, head, "demo-skill", "token")
except RuntimeError as error:
    assert str(error) == "GitHub compare failed"
else:
    raise AssertionError("compare failure was hidden")

requests = []


def paginated_request(method, url, token, payload=None):
    requests.append((method, url, payload))
    if method == "GET" and url.endswith("page=1"):
        return [{"id": index, "user": {"login": "someone"}, "body": "other"} for index in range(100)]
    if method == "GET" and url.endswith("page=2"):
        return [{"id": 9, "user": {"login": "github-actions[bot]"}, "body": module.MARKER}]
    return {}


module.github_json = paginated_request
module.sync_comment("owner/repo", "42", body, "token")
assert requests[0] == ("GET", "https://api.github.com/repos/owner/repo/issues/42/comments?per_page=100&page=1", None)
assert requests[1] == ("GET", "https://api.github.com/repos/owner/repo/issues/42/comments?per_page=100&page=2", None)
assert requests[-1] == ("PATCH", "https://api.github.com/repos/owner/repo/issues/comments/9", {"body": body})

requests = []


def create_request(method, url, token, payload=None):
    requests.append((method, url, payload))
    if method == "GET":
        return []
    return {}


module.github_json = create_request
module.sync_comment("owner/repo", "42", body, "token")
assert requests == [
    ("GET", "https://api.github.com/repos/owner/repo/issues/42/comments?per_page=100&page=1", None),
    ("POST", "https://api.github.com/repos/owner/repo/issues/42/comments", {"body": body}),
]
