"""sync-sources.py 提交 / PR 编排测试与真实 Git 沙箱集成测试。

纯标准库实现（unittest.mock、tempfile、subprocess），可直跑：

    python3 scripts/tests/test_sync_sources.py

覆盖：
- 场景 A：上游有更新 + 首次创建 PR（新分支、提交身份/message、-u 推送、PR、评论、环境恢复）
- 场景 B：上游有更新 + 远程分支与 PR 已存在（--force 推送、复用 PR）
- 场景 C：源无更新（不触发任何 git/PR/评论操作）
- 场景 D：单源不变量防御（changed_sources 抛出 ValueError）
- 场景 E：执行异常后的清理保证（switch 回原分支 + restore 工作区）
- test_git_commit_sandbox：真实 git 沙箱验证提交对象（作者、message、文件集合）
- renovate-skill-diff CLI 端到端：评论内容、粘性 PATCH / POST、token 环境变量兼容
"""
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest.mock as mock
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


sync_sources = load_module("sync_sources", ROOT / "scripts" / "sync-sources.py")
diff = load_module("renovate_skill_diff", ROOT / "scripts" / "renovate-skill-diff.py")

SOURCE = "demo-source"
BRANCH = "automation/nvfetcher/demo-source"
COMMITTER = "github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>"
COMMIT_MSG = "chore(nvfetcher): update demo-source"

BASELINE = {
    "demo-source": {"version": "v1.0.0", "src": {"owner": "example", "repo": "demo-source", "rev": "v1.0.0"}},
    "other-source": {"version": "v2.0.0", "src": {"owner": "example", "repo": "other-source", "rev": "v2.0.0"}},
}
HEAD = {
    "demo-source": {"version": "v1.1.0", "src": {"owner": "example", "repo": "demo-source", "rev": "v1.1.0"}},
    "other-source": {"version": "v2.0.0", "src": {"owner": "example", "repo": "other-source", "rev": "v2.0.0"}},
}

GIT_FILES = ("_sources/generated.json", "_sources/generated.nix")


@contextmanager
def patched(**replacements):
    """临时替换 sync_sources 模块属性，退出时恢复原值。"""
    originals = {name: getattr(sync_sources, name) for name in replacements}
    for name, value in replacements.items():
        setattr(sync_sources, name, value)
    try:
        yield
    finally:
        for name, original in originals.items():
            setattr(sync_sources, name, original)


def never_called(*_args, **_kwargs):
    raise AssertionError("该函数在此场景中不应当被调用")


def git_op(call: tuple) -> bool:
    return call[:1] == ("git",)


def git_action(call: tuple) -> str:
    return call[1]


def commit_call() -> tuple:
    return (
        "git", "-c", "user.name=github-actions[bot]", "-c",
        "user.email=41898282+github-actions[bot]@users.noreply.github.com",
        "commit", "-m", COMMIT_MSG,
    )


def restore_call() -> tuple:
    return ("git", "restore", "--source=HEAD", "--", *GIT_FILES)


def index_of(calls, pattern):
    found = [i for i, call in enumerate(calls) if call == pattern]
    assert found, f"缺少 git 调用 {pattern!r}，实际调用：{calls}"
    return found[0]


def test_first_pr_flow():
    """场景 A：上游有更新且无远程分支/PR → 新分支、提交、-u 推送、建 PR、评论、环境恢复。"""
    git_calls = []
    pr_calls = []
    comment_calls = []

    def record_run(*args):
        git_calls.append(args)

    def record_create(branch, source):
        pr_calls.append((branch, source))
        return "42"

    def record_comment(base_file, head_file, source, pull_request):
        with open(base_file, encoding="utf-8") as fh:
            assert json.load(fh) == BASELINE
        with open(head_file, encoding="utf-8") as fh:
            assert json.load(fh) == HEAD
        comment_calls.append((source, pull_request))

    with tempfile.TemporaryDirectory() as tmp:
        generated = Path(tmp) / "generated.json"
        generated.write_text(json.dumps(HEAD), encoding="utf-8")
        with patched(
            run=record_run,
            output=never_called,
            nvfetcher_run=lambda *_: None,
            GENERATED_JSON=generated,
            remote_branch_exists=lambda branch: False,
            gh_pr_number=lambda branch: "",
            create_pull_request=record_create,
            sync_comment=record_comment,
        ):
            sync_sources.sync_source(SOURCE, Path(tmp) / "nvfetcher.toml", "main", json.dumps(BASELINE))

    switch = index_of(git_calls, ("git", "switch", "-C", BRANCH, "origin/main"))
    add = index_of(git_calls, ("git", "add", "--", *GIT_FILES))
    commit = index_of(git_calls, commit_call())
    push = index_of(git_calls, ("git", "push", "-u", "origin", "HEAD:" + BRANCH))
    switch_back = index_of(git_calls, ("git", "switch", "main"))
    assert git_calls[0] == restore_call(), "流程应以工作区预检 restore 开始"
    assert git_calls[-1] == restore_call(), "流程应以工作区恢复 restore 结束"
    assert switch < add < commit < push < switch_back < len(git_calls) - 1, git_calls
    assert pr_calls == [(BRANCH, SOURCE)]
    assert comment_calls == [(SOURCE, "42")]


def test_sticky_existing_pr_flow():
    """场景 B：远程分支与 PR 已存在 → --force 推送并复用已有 PR，不新建。"""
    git_calls = []
    pr_number_calls = []
    create_calls = []
    comment_calls = []

    def record_run(*args):
        git_calls.append(args)

    def record_pr_number(branch):
        pr_number_calls.append(branch)
        return "42"

    def record_create(branch, source):
        create_calls.append((branch, source))
        return "99"

    def record_comment(base_file, head_file, source, pull_request):
        comment_calls.append((source, pull_request))

    with tempfile.TemporaryDirectory() as tmp:
        generated = Path(tmp) / "generated.json"
        generated.write_text(json.dumps(HEAD), encoding="utf-8")
        with patched(
            run=record_run,
            nvfetcher_run=lambda *_: None,
            GENERATED_JSON=generated,
            remote_branch_exists=lambda branch: True,
            gh_pr_number=record_pr_number,
            create_pull_request=record_create,
            sync_comment=record_comment,
        ):
            sync_sources.sync_source(SOURCE, Path(tmp) / "nvfetcher.toml", "main", json.dumps(BASELINE))

    push = index_of(git_calls, ("git", "push", "--force", "origin", "HEAD:" + BRANCH))
    assert push < index_of(git_calls, ("git", "switch", "main")), git_calls
    assert not any(git_action(call) == "push" and "-u" in call for call in git_calls), git_calls
    assert pr_number_calls == [BRANCH]
    assert create_calls == [], "已有 PR 时不应调用 create_pull_request"
    assert comment_calls == [(SOURCE, "42")], "应复用已有 PR 号同步评论"


def test_up_to_date_no_ops():
    """场景 C：源无更新 → 除预检 restore 外不触发任何 git/PR/评论操作。"""
    git_calls = []

    with tempfile.TemporaryDirectory() as tmp:
        generated = Path(tmp) / "generated.json"
        generated.write_text(json.dumps(BASELINE), encoding="utf-8")
        with patched(
            run=lambda *args: git_calls.append(args),
            nvfetcher_run=lambda *_: None,
            GENERATED_JSON=generated,
            remote_branch_exists=never_called,
            gh_pr_number=never_called,
            create_pull_request=never_called,
            sync_comment=never_called,
        ):
            sync_sources.sync_source(SOURCE, Path(tmp) / "nvfetcher.toml", "main", json.dumps(BASELINE))

    assert not any(git_action(call) in ("switch", "commit", "push") for call in git_calls), git_calls


def test_single_source_invariant():
    """场景 D：head 混入非预期源改动 → changed_sources 抛出 ValueError，不做任何提交/推送。"""
    intruder_head = {
        **HEAD,
        "other-source": {"version": "v9.9.9", "src": {"owner": "example", "repo": "other-source", "rev": "v9.9.9"}},
    }
    git_calls = []

    with tempfile.TemporaryDirectory() as tmp:
        generated = Path(tmp) / "generated.json"
        generated.write_text(json.dumps(intruder_head), encoding="utf-8")
        with patched(
            run=lambda *args: git_calls.append(args),
            nvfetcher_run=lambda *_: None,
            GENERATED_JSON=generated,
            remote_branch_exists=never_called,
            gh_pr_number=never_called,
            create_pull_request=never_called,
            sync_comment=never_called,
        ):
            try:
                sync_sources.sync_source(SOURCE, Path(tmp) / "nvfetcher.toml", "main", json.dumps(BASELINE))
            except ValueError as error:
                message = str(error)
                assert "demo-source" in message and "other-source" in message, message
            else:
                raise AssertionError("混入其它源改动时 changed_sources 未抛出 ValueError")

    assert not any(git_action(call) in ("switch", "commit", "push") for call in git_calls), git_calls

    # 直接调用：仅目标源变化时应通过
    assert sync_sources.changed_sources(BASELINE, HEAD, SOURCE) == [SOURCE]


def test_failure_cleanup():
    """场景 E：git push 失败 → main 循环确保 switch 回原分支并 restore 工作区文件。"""
    git_calls = []

    def record_run(*args):
        git_calls.append(args)
        if args[:2] == ("git", "push"):
            raise subprocess.CalledProcessError(1, args)

    def fake_output(*args):
        if args[-1] == "--show-current":
            return "main"
        return ""

    with tempfile.TemporaryDirectory() as tmp:
        config = Path(tmp) / "nvfetcher.toml"
        generated = Path(tmp) / "generated.json"
        generated.write_text(json.dumps(BASELINE), encoding="utf-8")

        def nvfetcher_writes_head(*_args):
            generated.write_text(json.dumps(HEAD), encoding="utf-8")

        with patched(
            run=record_run,
            output=fake_output,
            nvfetcher_run=nvfetcher_writes_head,
            GENERATED_JSON=generated,
            remote_branch_exists=lambda branch: False,
            gh_pr_number=never_called,
            create_pull_request=never_called,
            sync_comment=never_called,
        ):
            with mock.patch("sys.argv", ["sync-sources.py", "--config", str(config), "--sources", SOURCE]):
                try:
                    sync_sources.main()
                except SystemExit as exc:
                    assert exc.code == 1
                else:
                    raise AssertionError("push 失败后 main 应以非零状态退出")

    assert git_action(git_calls[-1]) == "restore", "失败后必须 restore 工作区"
    assert git_calls[-2] == ("git", "switch", "main"), "失败后必须 switch 回原分支"
    push_index = index_of(git_calls, ("git", "push", "-u", "origin", "HEAD:" + BRANCH))
    assert index_of(git_calls, commit_call()) < push_index < len(git_calls) - 2, git_calls


def test_git_commit_sandbox():
    """真实 Git 沙箱：执行真实 switch/add/commit，核验提交对象身份、message 与文件集合。"""
    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp)
        generated = repo / "_sources" / "generated.json"
        generated_nix = repo / "_sources" / "generated.nix"
        generated.parent.mkdir()
        generated.write_text(json.dumps(BASELINE), encoding="utf-8")
        generated_nix.write_text("generated = {}\n", encoding="utf-8")

        def git(*args):
            subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True, text=True)

        def git_out(*args):
            return subprocess.run(
                ["git", "-C", str(repo), *args], check=True, capture_output=True, text=True
            ).stdout

        git("init", "-b", "main")
        git("config", "user.name", "Local Tester")
        git("config", "user.email", "tester@example.com")
        git("config", "commit.gpgsign", "false")
        git("add", "-A")
        git("commit", "-m", "init baseline")
        git("update-ref", "refs/remotes/origin/main", git_out("rev-parse", "HEAD").strip())

        def nvfetcher_writes_head(*_args):
            generated.write_text(json.dumps(HEAD), encoding="utf-8")
            generated_nix.write_text("generated = { version = \"v1.1.0\"; }\n", encoding="utf-8")

        push_calls = []
        comment_calls = []

        original_run = sync_sources.run

        def sandbox_run(*args):
            if args[:2] == ("git", "push"):
                push_calls.append(args)
                return
            original_run(*args)

        with patched(
            ROOT=repo,
            GENERATED_JSON=generated,
            run=sandbox_run,
            nvfetcher_run=nvfetcher_writes_head,
            remote_branch_exists=lambda branch: False,
            gh_pr_number=lambda branch: "",
            create_pull_request=lambda branch, source: "7",
            sync_comment=lambda *_args: comment_calls.append(_args),
        ):
            sync_sources.sync_source(SOURCE, Path(tmp) / "nvfetcher.toml", "main", json.dumps(BASELINE))

        assert git_out("branch", "--show-current").strip() == "main", "处理完成后应回到原分支"
        log = git_out("log", "-1", "--format=%an <%ae>|%s", BRANCH).strip()
        assert log == f"{COMMITTER}|{COMMIT_MSG}", f"提交对象身份/message 不符：{log!r}"
        files = git_out("diff-tree", "--no-commit-id", "--name-only", "-r", BRANCH).split()
        assert files == list(GIT_FILES), f"提交文件集合不符：{files}"
        assert git_out("status", "--porcelain") == "", "工作区不应有残留改动"
        assert len(push_calls) == 1 and push_calls[0] == ("git", "push", "-u", "origin", "HEAD:" + BRANCH), push_calls
        assert len(comment_calls) == 1


def _skill_source(name: str, version: str) -> dict:
    return {"version": version, "src": {"owner": "example", "repo": name, "rev": version}}


def _write_diff_fixture(tmp) -> tuple[Path, Path]:
    tmp = Path(tmp)
    base = {"demo-skill": _skill_source("demo-skill", "v1.0.0"), "other-skill": _skill_source("other-skill", "v2.0.0")}
    head = {"demo-skill": _skill_source("demo-skill", "v1.1.0"), "other-skill": _skill_source("other-skill", "v2.0.0")}
    base_file = tmp / "base.json"
    head_file = tmp / "head.json"
    base_file.write_text(json.dumps(base), encoding="utf-8")
    head_file.write_text(json.dumps(head), encoding="utf-8")
    return base_file, head_file


def _compare_response() -> dict:
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


def _run_diff_cli(tmp: Path, comments_get, env_extra) -> list:
    base_file, head_file = _write_diff_fixture(tmp)
    requests = []

    def fake_github_json(method, url, token, payload=None):
        requests.append((method, url, token, payload))
        if method == "GET":
            if "/compare/" in url:
                return _compare_response()
            return comments_get
        return {}

    diff.github_json = fake_github_json
    with mock.patch.dict(os.environ, env_extra), mock.patch(
        "sys.argv",
        [
            "renovate-skill-diff.py",
            "--base-file", str(base_file),
            "--head-file", str(head_file),
            "--source", "demo-skill",
            "--pull-request", "42",
        ],
    ):
        diff.main()
    return requests


def _body_of(requests) -> str:
    write_call = next(req for req in requests if req[0] in ("PATCH", "POST"))
    return write_call[3]["body"]


def test_cli_sticky_patch():
    """评论端到端：PR 已存在带标记的旧评论 → 单次 PATCH 更新；正文含 marker/链接/技能 diff，不含无关文件。"""
    with tempfile.TemporaryDirectory() as tmp:
        marker_comment = [{"id": 9, "user": {"login": "github-actions[bot]"}, "body": diff.MARKER}]
        requests = _run_diff_cli(
            tmp,
            marker_comment,
            {"GITHUB_TOKEN": "tok", "GITHUB_REPOSITORY": "owner/repo"},
        )

    methods = [req[0] for req in requests]
    assert methods == ["GET", "GET", "PATCH"], f"应复用旧评论只 PATCH 一次：{methods}"
    assert requests[-1][2] == "tok"
    body = _body_of(requests)
    assert diff.MARKER in body
    assert "`demo-skill`: `v1.0.0` → `v1.1.0`" in body
    assert "https://github.com/example/demo-skill/compare/v1.0.0...v1.1.0" in body
    assert "skills/demo/SKILL.md" in body
    assert "README.md" not in body
    assert "other-skill" not in body


def test_cli_post_when_no_marker():
    """评论端到端：无既有标记评论 → 走 POST 新建评论，正文同样完整。"""
    with tempfile.TemporaryDirectory() as tmp:
        requests = _run_diff_cli(tmp, [], {"GITHUB_TOKEN": "tok", "GITHUB_REPOSITORY": "owner/repo"})

    methods = [req[0] for req in requests]
    assert methods == ["GET", "GET", "POST"], f"无旧评论时应 POST 新建：{methods}"
    assert diff.MARKER in _body_of(requests)


def test_token_env_compat():
    """token 环境变量兼容：仅 GH_TOKEN 可用；两者皆缺时给出清晰错误并退出非零。"""
    with tempfile.TemporaryDirectory() as tmp:
        base_file, head_file = _write_diff_fixture(tmp)

        # 仅设置 GH_TOKEN → 流程可走通，token 正确透传
        seen_tokens = []

        def fake(method, url, token, payload=None):
            seen_tokens.append(token)
            if method == "GET" and "/compare/" in url:
                return {"files": []}
            if method == "GET":
                return []
            return {}

        diff.github_json = fake
        with mock.patch.dict(
            os.environ,
            {"GITHUB_TOKEN": "", "GH_TOKEN": "tok-gh", "GITHUB_REPOSITORY": "owner/repo"},
        ), mock.patch(
            "sys.argv",
            ["renovate-skill-diff.py", "--base-file", str(base_file), "--head-file", str(head_file),
             "--source", "demo-skill", "--pull-request", "42"],
        ):
            diff.main()
        assert seen_tokens and all(token == "tok-gh" for token in seen_tokens), seen_tokens

        # 两者皆缺 → SystemExit(1) 且 stderr 有提示
        def never(*_args, **_kwargs):
            raise AssertionError("缺少 token 时不应发起任何 API 调用")

        diff.github_json = never
        stderr = io.StringIO()
        with mock.patch.dict(os.environ, {"GITHUB_TOKEN": "", "GH_TOKEN": ""}), mock.patch(
            "sys.argv",
            ["renovate-skill-diff.py", "--base-file", str(base_file), "--head-file", str(head_file),
             "--source", "demo-skill", "--pull-request", "42"],
        ), mock.patch("sys.stderr", stderr):
            try:
                diff.main()
            except SystemExit as exc:
                assert exc.code == 1
            else:
                raise AssertionError("缺少 token 时未以非零状态退出")
        assert "GITHUB_TOKEN 或 GH_TOKEN" in stderr.getvalue()


def main() -> None:
    tests = [
        test_first_pr_flow,
        test_sticky_existing_pr_flow,
        test_up_to_date_no_ops,
        test_single_source_invariant,
        test_failure_cleanup,
        test_git_commit_sandbox,
        test_cli_sticky_patch,
        test_cli_post_when_no_marker,
        test_token_env_compat,
    ]
    failures = []
    for test in tests:
        try:
            test()
        except Exception as error:  # noqa: BLE001 —— 直跑脚本，逐用例报告
            failures.append((test.__name__, error))
            print(f"FAIL {test.__name__}: {error!r}", file=sys.stderr)
        else:
            print(f"PASS {test.__name__}")
    if failures:
        print(f"{len(failures)}/{len(tests)} 个测试失败", file=sys.stderr)
        raise SystemExit(1)
    print(f"全部 {len(tests)} 个测试通过")


if __name__ == "__main__":
    main()
