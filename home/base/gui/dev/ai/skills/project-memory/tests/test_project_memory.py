#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import tempfile
import time
import unicodedata
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts" / "project_memory.py"


class ProjectMemoryCliTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.sessions = self.root / "sessions"
        self.cache = self.root / "cache"
        self.config = self.root / "config"
        self.project = self.make_repo("project", "git@github.com:Owner/Example.git")
        self.other = self.make_repo("other", "https://github.com/other/example.git")

    def tearDown(self):
        self.temp.cleanup()

    def make_repo(self, name, remote):
        path = self.root / name
        path.mkdir()
        self.run_git(path, "init")
        self.run_git(path, "remote", "add", "origin", remote)
        return path

    def run_git(self, cwd, *args):
        subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True)

    def write_session(
        self,
        name,
        session_id,
        cwd,
        entries=(),
        timestamp="2026-07-10T00:00:00Z",
    ):
        path = self.sessions / name
        path.parent.mkdir(parents=True, exist_ok=True)
        header = {
            "type": "session",
            "version": 3,
            "id": session_id,
            "timestamp": timestamp,
            "cwd": str(cwd),
        }
        path.write_text("\n".join(json.dumps(item) for item in (header, *entries)) + "\n")
        return path

    def cli(self, *args, expect=0, parse_json=True):
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--sessions-dir", str(self.sessions),
                "--cache-dir", str(self.cache),
                "--config-dir", str(self.config),
                "--project-dir", str(self.project),
                *args,
            ],
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, expect, result.stderr)
        if expect or not parse_json:
            return result
        return json.loads(result.stdout)

    def test_rebuild_index_normalizes_remote_and_status_isolates_current_project(self):
        self.write_session("one.jsonl", "one", self.project)
        self.write_session("two.jsonl", "two", self.other)

        rebuilt = self.cli("rebuild-index")
        self.assertEqual(rebuilt["indexed"], 2)
        self.assertEqual(rebuilt["unresolved"], 0)
        index = json.loads((self.cache / "index-v1.json").read_text())
        identities = {item["session_id"]: item["repo_identity"] for item in index["sessions"]}
        self.assertEqual(identities["one"], "github.com/owner/example")
        self.assertEqual(identities["two"], "github.com/other/example")

        status = self.cli("status")
        self.assertEqual(status["sessions"], 1)
        self.assertEqual(status["unseen"], 1)
        self.assertEqual(status["unresolved"], 0)
        self.assertEqual(oct((self.cache / "index-v1.json").stat().st_mode & 0o777), "0o600")

        self.run_git(self.project, "remote", "set-url", "origin", "https://github.com/owner/renamed.git")
        self.cli("rebuild-index")
        index = json.loads((self.cache / "index-v1.json").read_text())
        identity = next(item["repo_identity"] for item in index["sessions"] if item["session_id"] == "one")
        self.assertEqual(identity, "github.com/owner/renamed")

        rejected = self.cli(
            "mark-reviewed",
            "two",
            "--status",
            "reviewed",
            expect=1,
        )
        self.assertIn("session not found in current project", rejected.stderr)

    def test_rebuild_index_supports_git_without_remote_and_non_git_projects(self):
        no_remote = self.root / "no-remote"
        no_remote.mkdir()
        self.run_git(no_remote, "init")
        plain = self.root / "plain"
        plain.mkdir()
        self.write_session("no-remote.jsonl", "no-remote", no_remote)
        self.write_session("plain.jsonl", "plain", plain)

        self.cli("rebuild-index")
        index = json.loads((self.cache / "index-v1.json").read_text())
        identities = {item["session_id"]: item["repo_identity"] for item in index["sessions"]}
        self.assertEqual(identities["no-remote"], str(no_remote.resolve()))
        self.assertEqual(identities["plain"], str(plain.resolve()))

    def test_search_respects_real_pi_message_schema_lineage_tools_and_redaction(self):
        entries = (
            {"type": "message", "id": "u1", "timestamp": "2026-07-10T01:00:00Z", "message": {"role": "user", "content": [{"type": "text", "text": "Need cache repair"}]}},
            {"type": "message", "id": "a1", "parentId": "u1", "timestamp": "2026-07-10T01:01:00Z", "message": {"role": "assistant", "content": [{"type": "text", "text": "cache repair completed"}, {"type": "toolCall", "id": "call-1", "name": "bash", "arguments": {"command": "run internal-maintenance-command"}}]}},
            {"type": "message", "id": "old", "parentId": "u1", "timestamp": "2026-07-10T01:02:00Z", "message": {"role": "assistant", "content": [{"type": "text", "text": "cache repair abandoned branch"}]}},
            {"type": "compaction", "id": "sum", "parentId": "a1", "timestamp": "2026-07-10T01:03:00Z", "summary": "cache repair summary"},
            {"type": "message", "id": "tool", "parentId": "sum", "timestamp": "2026-07-10T01:04:00Z", "message": {"role": "toolResult", "toolCallId": "call-1", "toolName": "bash", "content": [{"type": "text", "text": "Authorization: Basic dXNlcjpwYXNz cache repair tool result"}], "isError": False}},
            {"type": "message", "id": "final", "parentId": "tool", "timestamp": "2026-07-10T01:05:00Z", "message": {"role": "assistant", "content": [{"type": "text", "text": "password=\"correct horse\" cache repair verified"}]}},
        )
        self.write_session("search.jsonl", "search", self.project, entries)
        self.write_session(
            "other-search.jsonl",
            "other-search",
            self.other,
            ({"type": "message", "id": "other-entry", "message": {"role": "user", "content": "cross project evidence"}},),
        )

        found = self.cli("search", "cache repair")
        self.assertEqual([item["entry_id"] for item in found["results"]], ["u1", "a1", "final"])
        self.assertEqual(found["results"][0]["branch_status"], "active")
        self.assertEqual(self.cli("search", "internal-maintenance-command")["results"], [])
        self.assertEqual(self.cli("search", "tool result")["results"], [])
        summaries = self.cli("search", "summary")
        self.assertEqual(summaries["results"][0]["entry_id"], "sum")
        self.assertEqual(summaries["results"][0]["evidence"], False)
        self.assertNotIn("dXNlcjpwYXNz", json.dumps(found))
        self.assertNotIn("correct horse", json.dumps(found))

        all_branches = self.cli("search", "abandoned", "--all-branches")
        self.assertEqual(all_branches["results"][0]["entry_id"], "old")
        self.assertEqual(all_branches["results"][0]["branch_status"], "abandoned")
        abandoned = self.cli("show", "search:old", "--all-branches")
        self.assertEqual(abandoned["context"][-1]["entry_id"], "old")
        self.assertEqual(abandoned["context"][-1]["branch_status"], "abandoned")

        cross_project = self.cli("search", "cross project", "--all-projects")
        self.assertEqual(cross_project["results"][0]["session_id"], "other-search")
        self.assertEqual(
            self.cli("show", "other-search:other-entry", "--all-projects")["entry_id"],
            "other-entry",
        )

        tool_call = self.cli("search", "internal-maintenance-command", "--include-tools")
        self.assertEqual(tool_call["results"][0]["entry_id"], "a1")
        self.assertEqual(tool_call["results"][0]["kind"], "tool")
        tools = self.cli("search", "tool result", "--include-tools")
        self.assertEqual(tools["results"][0]["entry_id"], "tool")
        self.assertEqual(tools["results"][0]["role"], "toolResult")
        self.assertIn("[REDACTED]", tools["results"][0]["snippet"])
        self.assertNotIn("dXNlcjpwYXNz", json.dumps(tools))

        shown = self.cli("show", "search:final")
        self.assertEqual(shown["entry_id"], "final")
        self.assertNotIn("correct horse", json.dumps(shown))
        self.assertNotIn("dXNlcjpwYXNz", json.dumps(shown))
        shown_tools = self.cli("show", "search:final", "--include-tools")
        self.assertTrue(any(item["entry_id"] == "tool" for item in shown_tools["context"]))
        self.assertNotIn("dXNlcjpwYXNz", json.dumps(shown_tools))

    def test_cli_rejects_empty_query_invalid_limits_and_candidate_count(self):
        self.write_session("one.jsonl", "one", self.project)

        self.assertIn("query must not be empty", self.cli("search", "   ", expect=1).stderr)
        self.assertEqual(self.cli("search", "query", "--limit", "0", expect=2).returncode, 2)
        self.assertEqual(self.cli("mine", "--limit", "0", expect=2).returncode, 2)
        self.assertEqual(
            self.cli(
                "mark-reviewed",
                "one",
                "--status",
                "pending",
                "--candidate-count",
                "-1",
                expect=2,
            ).returncode,
            2,
        )

    def test_mine_limits_summaries_and_prioritizes_recently_updated_session(self):
        summaries = tuple(
            {
                "type": "compaction",
                "id": f"summary-{number}",
                "parentId": f"summary-{number - 1}" if number > 1 else None,
                "summary": f"summary text {number}",
            }
            for number in range(1, 5)
        )
        older_created = self.write_session(
            "older-created.jsonl",
            "older-created",
            self.project,
            entries=summaries,
            timestamp="2025-01-01T00:00:00Z",
        )
        newer_created = self.write_session(
            "newer-created.jsonl",
            "newer-created",
            self.project,
            timestamp="2026-01-01T00:00:00Z",
        )
        os.utime(newer_created, (1_700_000_000, 1_700_000_000))
        os.utime(older_created, (1_800_000_000, 1_800_000_000))

        mined = self.cli("mine", "--limit", "1")
        self.assertEqual(mined["sessions"][0]["session_id"], "older-created")
        summary_ids = [
            item["entry_id"]
            for item in mined["sessions"][0]["items"]
            if item["kind"] == "summary"
        ]
        self.assertEqual(summary_ids, ["summary-3", "summary-4"])

    def test_mine_filters_by_updated_time_with_relative_and_absolute_bounds(self):
        old = self.write_session("old.jsonl", "old", self.project)
        boundary = self.write_session("boundary.jsonl", "boundary", self.project)
        recent = self.write_session("recent.jsonl", "recent", self.project)
        os.utime(old, (1_749_988_800, 1_749_988_800))       # 2025-06-15T12:00:00Z
        os.utime(boundary, (1_750_852_800, 1_750_852_800))  # 2025-06-25T12:00:00Z
        os.utime(recent, (time.time() - 14 * 86_400,) * 2)

        since = self.cli("mine", "--since", "2025-06-25T12:00:00Z")
        until = self.cli("mine", "--until", "2025-06-25T12:00:00Z")
        until_date = self.cli("mine", "--until", "2025-06-25")
        relative = self.cli("mine", "--since", "15d")

        self.assertEqual(
            {item["session_id"] for item in since["sessions"]},
            {"boundary", "recent"},
        )
        self.assertEqual(
            {item["session_id"] for item in until["sessions"]},
            {"old", "boundary"},
        )
        self.assertEqual(
            {item["session_id"] for item in until_date["sessions"]},
            {"old", "boundary"},
        )
        self.assertEqual(
            [item["session_id"] for item in relative["sessions"]],
            ["recent"],
        )
        invalid = self.cli(
            "mine",
            "--since",
            "2025-06-26T00:00:00Z",
            "--until",
            "2025-06-25T00:00:00Z",
            expect=1,
        )
        self.assertIn("--since must not be later than --until", invalid.stderr)

    def test_mine_signals_rank_problem_sessions_and_emit_evidence_episodes(self):
        problem = self.write_session(
            "problem.jsonl",
            "problem",
            self.project,
            entries=(
                {"type": "message", "id": "u1", "message": {"role": "user", "content": "请检查构建命令失败的真正根因，不要只处理表面错误"}},
                {"type": "message", "id": "a1", "parentId": "u1", "message": {"role": "assistant", "content": [{"type": "text", "text": "我先执行命令。"}, {"type": "toolCall", "id": "call-1", "name": "bash", "arguments": {"command": "nix build"}}]}},
                {"type": "message", "id": "t1", "parentId": "a1", "message": {"role": "toolResult", "toolCallId": "call-1", "toolName": "bash", "content": "Authorization: Bearer secret-token\nbuild failed", "isError": True}},
                {"type": "message", "id": "b1", "parentId": "t1", "message": {"role": "bashExecution", "command": "nix build", "output": "exit 1", "exitCode": 1}},
                {"type": "message", "id": "a2", "parentId": "b1", "message": {"role": "assistant", "content": "应该只是网络波动。"}},
                {"type": "message", "id": "u2", "parentId": "a2", "message": {"role": "user", "content": "不对，我已经说过要先验证根因，不要继续猜测。"}},
                {"type": "message", "id": "a3", "parentId": "u2", "message": {"role": "assistant", "content": "我会检查最终配置。"}},
                {"type": "message", "id": "u3", "parentId": "a3", "message": {"role": "user", "content": "请检查构建命令失败的真正根本原因，不要只处理表面错误。"}},
                {"type": "message", "id": "done", "parentId": "u3", "message": {"role": "assistant", "content": "已验证根因。"}},
            ),
        )
        quiet = self.write_session(
            "quiet.jsonl",
            "quiet",
            self.project,
            entries=({"type": "message", "id": "quiet-user", "message": {"role": "user", "content": "列出文件"}},),
        )
        os.utime(problem, (1_700_000_000, 1_700_000_000))
        os.utime(quiet, (1_800_000_000, 1_800_000_000))

        mined = self.cli("mine", "--signals", "--limit", "1")
        session = mined["sessions"][0]
        by_kind = {item["kind"]: item for item in session["signals"]}

        self.assertEqual(session["session_id"], "problem")
        self.assertEqual(
            session["signal_counts"],
            {"command_failure": 1, "repeated_user_prompt": 1, "user_correction": 1},
        )
        self.assertEqual(session["problem_score"], 8)
        self.assertEqual(by_kind["command_failure"]["entry_ids"], ["t1", "b1"])
        self.assertEqual(by_kind["repeated_user_prompt"]["entry_ids"], ["u1", "u3"])
        self.assertEqual(by_kind["repeated_user_prompt"]["similarity"], 0.96)
        self.assertEqual(by_kind["user_correction"]["entry_ids"], ["u2"])
        self.assertIn("a2", {item["entry_id"] for item in by_kind["user_correction"]["episode"]})
        self.assertIn("u2", {item["entry_id"] for item in by_kind["user_correction"]["episode"]})
        self.assertNotIn("secret-token", json.dumps(mined))

        streamed = self.cli("mine", "--signals", "--limit", "1", "--format", "ndjson", parse_json=False)
        lines = [json.loads(line) for line in streamed.stdout.splitlines()]
        self.assertEqual([item["type"] for item in lines], ["meta", "session", "signal", "signal", "signal"])
        self.assertEqual({item["kind"] for item in lines[2:]}, set(by_kind))
        rejected = self.cli("mine", "--signals", "--transcript", expect=2)
        self.assertEqual(rejected.returncode, 2)

    def test_signal_detection_respects_branches_unicode_and_full_prompt_text(self):
        self.write_session(
            "branches.jsonl",
            "branches",
            self.project,
            entries=(
                {"type": "message", "id": "root", "message": {"role": "user", "content": "诊断失败"}},
                {"type": "message", "id": "old-assistant", "parentId": "root", "message": {"role": "assistant", "content": "旧分支"}},
                {"type": "message", "id": "active-assistant", "parentId": "root", "message": {"role": "assistant", "content": "当前分支"}},
                {"type": "message", "id": "old-error", "parentId": "old-assistant", "message": {"role": "toolResult", "content": "old failed", "isError": True}},
                {"type": "message", "id": "active-error", "parentId": "active-assistant", "message": {"role": "toolResult", "content": "active failed", "isError": True}},
                {"type": "message", "id": "done", "parentId": "active-error", "message": {"role": "assistant", "content": "完成"}},
            ),
        )
        unicode_prompt = "Café résumé déjà à côté"
        self.write_session(
            "unicode.jsonl",
            "unicode",
            self.project,
            entries=(
                {"type": "message", "id": "unicode-1", "message": {"role": "user", "content": unicode_prompt}},
                {"type": "message", "id": "unicode-answer", "parentId": "unicode-1", "message": {"role": "assistant", "content": "处理中"}},
                {"type": "message", "id": "unicode-2", "parentId": "unicode-answer", "message": {"role": "user", "content": unicodedata.normalize("NFD", unicode_prompt)}},
                {"type": "message", "id": "unicode-done", "parentId": "unicode-2", "message": {"role": "assistant", "content": "完成"}},
            ),
        )
        shared = "请检查配置。" * 100
        self.write_session(
            "long.jsonl",
            "long",
            self.project,
            entries=(
                {"type": "message", "id": "long-1", "message": {"role": "user", "content": shared + "保留旧配置"}},
                {"type": "message", "id": "long-answer", "parentId": "long-1", "message": {"role": "assistant", "content": "处理中"}},
                {"type": "message", "id": "long-2", "parentId": "long-answer", "message": {"role": "user", "content": shared + "删除全部配置"}},
                {"type": "message", "id": "long-done", "parentId": "long-2", "message": {"role": "assistant", "content": "完成"}},
            ),
        )

        mined = self.cli("mine", "--signals", "--all-branches", "--limit", "10")
        sessions = {item["session_id"]: item for item in mined["sessions"]}

        self.assertEqual(sessions["branches"]["signal_counts"], {"command_failure": 2})
        branch_signals = sessions["branches"]["signals"]
        self.assertEqual(
            [{item["branch_status"] for item in signal["episode"]} for signal in branch_signals],
            [{"abandoned"}, {"active"}],
        )
        self.assertEqual(sessions["unicode"]["signal_counts"], {"repeated_user_prompt": 1})
        self.assertNotIn("long", sessions)

    def test_mine_ndjson_streams_transcript_as_one_json_object_per_line(self):
        self.write_session(
            "stream.jsonl",
            "stream",
            self.project,
            entries=(
                {"type": "message", "id": "user", "message": {"role": "user", "content": "Find the root cause"}},
                {"type": "message", "id": "assistant", "parentId": "user", "message": {"role": "assistant", "content": "Verified the fix"}},
            ),
        )

        streamed = self.cli(
            "mine",
            "--transcript",
            "--format",
            "ndjson",
            parse_json=False,
        )
        lines = [json.loads(line) for line in streamed.stdout.splitlines()]

        self.assertEqual(lines[0], {"type": "meta", "project_identity": "github.com/owner/example"})
        self.assertEqual(
            lines[1],
            {"type": "session", "session_id": "stream", "status": "unseen"},
        )
        self.assertEqual([item["type"] for item in lines[2:]], ["transcript", "transcript"])
        self.assertEqual([item["entry_id"] for item in lines[2:]], ["user", "assistant"])
        self.assertEqual({item["session_id"] for item in lines[2:]}, {"stream"})
        self.assertEqual(
            self.cli("mine", "--transcript")["sessions"][0]["session_id"],
            "stream",
        )

    def test_transcript_mode_preserves_active_conversation_and_failures(self):
        self.write_session(
            "failure.jsonl",
            "failure",
            self.project,
            entries=(
                {"type": "message", "id": "user", "message": {"role": "user", "content": "Why does the Nix cache build locally?"}},
                {"type": "message", "id": "abandoned", "parentId": "user", "message": {"role": "assistant", "content": "abandoned diagnosis"}},
                {"type": "message", "id": "assistant", "parentId": "user", "message": {"role": "assistant", "content": [{"type": "text", "text": "I will check the cache trust."}, {"type": "toolCall", "id": "call-1", "name": "bash", "arguments": {"command": "nix store info"}}]}},
                {"type": "message", "id": "tool-error", "parentId": "assistant", "message": {"role": "toolResult", "toolCallId": "call-1", "toolName": "bash", "content": "Authorization: Bearer token-should-redact\ncache trust command failed", "isError": True}},
                {"type": "message", "id": "bash-error", "parentId": "tool-error", "message": {"role": "bashExecution", "command": "nix store info", "output": "exit 1: missing trusted key", "exitCode": 1}},
                {"type": "message", "id": "resolved", "parentId": "bash-error", "message": {"role": "assistant", "content": "The missing nix-community public key caused the local build."}},
            ),
        )

        mined = self.cli("mine", "--limit", "1", "--transcript")
        shown = self.cli("show", "--session", "failure", "--transcript")
        all_branches = self.cli("show", "--session", "failure", "--transcript", "--all-branches")

        transcript = mined["sessions"][0]["transcript"]
        self.assertEqual(
            [item["entry_id"] for item in transcript],
            ["user", "assistant", "tool-error", "bash-error", "resolved"],
        )
        self.assertEqual([item["role"] for item in transcript], ["user", "assistant", "toolResult", "bashExecution", "assistant"])
        self.assertIn("bash", transcript[1]["snippet"])
        self.assertTrue(transcript[2]["is_error"])
        self.assertTrue(transcript[3]["is_error"])
        self.assertEqual(shown["transcript"], transcript)
        self.assertEqual(
            [item["entry_id"] for item in all_branches["transcript"]],
            ["user", "abandoned", "assistant", "tool-error", "bash-error", "resolved"],
        )
        self.assertEqual(all_branches["transcript"][1]["branch_status"], "abandoned")
        self.assertNotIn("token-should-redact", json.dumps(transcript))

    def test_transcript_redacts_structured_credentials_and_marks_native_failures(self):
        self.write_session(
            "native-failure.jsonl",
            "native-failure",
            self.project,
            entries=(
                {"type": "message", "id": "user", "message": {"role": "user", "content": "Check the remote cache"}},
                {"type": "message", "id": "call", "parentId": "user", "message": {"role": "assistant", "content": [{"type": "toolCall", "id": "call-1", "name": "fetch", "arguments": {"headers": {"Authorization": "Basic dGVzdDpmaXh0dXJl"}}}]}},
                {"type": "message", "id": "assistant-error", "parentId": "call", "message": {"role": "assistant", "content": [], "stopReason": "error", "errorMessage": "provider request failed"}},
                {"type": "message", "id": "cancelled", "parentId": "assistant-error", "message": {"role": "bashExecution", "command": "sleep 30", "output": "", "cancelled": True}},
            ),
        )

        transcript = self.cli("mine", "--limit", "1", "--transcript")["sessions"][0]["transcript"]
        by_id = {item["entry_id"]: item for item in transcript}

        self.assertNotIn("dGVzdDpmaXh0dXJl", json.dumps(transcript))
        self.assertTrue(by_id["assistant-error"]["is_error"])
        self.assertEqual(by_id["assistant-error"]["snippet"], "provider request failed")
        self.assertTrue(by_id["cancelled"]["is_error"])

    def test_session_and_entry_selectors_narrow_show_and_search(self):
        previous = self.write_session(
            "previous.jsonl",
            "older",
            self.project,
            entries=(
                {"type": "message", "id": "previous-user", "message": {"role": "user", "content": "opening request"}},
                {"type": "message", "id": "previous-assistant", "parentId": "previous-user", "message": {"role": "assistant", "content": "intermediate response"}},
                {"type": "message", "id": "previous-last-user", "parentId": "previous-assistant", "message": {"role": "user", "content": "cache repair request"}},
            ),
        )
        current = self.write_session(
            "current.jsonl",
            "current",
            self.project,
            entries=({"type": "message", "id": "current-user", "message": {"role": "user", "content": "cache repair in current session"}},),
        )
        os.utime(previous, (1_700_000_000, 1_700_000_000))
        os.utime(current, (1_800_000_000, 1_800_000_000))
        current.write_text(current.read_text() + "{not-json}\n")

        shown = self.cli("show", "--session", "previous", "--entry", "last-user")
        by_prefix = self.cli("show", "--session", "ol", "--entry", "last-assistant")
        latest = self.cli("show", "--session", "latest", "--entry", "last-user")
        searched = self.cli("search", "cache repair", "--session", "previous")

        self.assertEqual(shown["session_id"], "older")
        self.assertEqual(shown["entry_id"], "previous-last-user")
        self.assertEqual(shown["context"][-1]["snippet"], "cache repair request")
        self.assertEqual(by_prefix["entry_id"], "previous-assistant")
        self.assertEqual(latest["session_id"], "current")
        self.assertEqual(latest["entry_id"], "current-user")
        self.assertEqual([item["session_id"] for item in searched["results"]], ["older"])
        self.assertEqual([item["entry_id"] for item in searched["results"]], ["previous-last-user"])
        self.assertEqual(searched["warnings"], [])

    def test_invalid_project_mapping_fails_without_overwriting_config(self):
        self.config.mkdir(parents=True)
        mapping = self.config / "projects.json"
        mapping.write_text("{not-json}\n")

        failed = self.cli("status", expect=1)
        self.assertIn("invalid project mapping", failed.stderr)
        self.assertEqual(mapping.read_text(), "{not-json}\n")

    def test_index_state_machine_mapping_and_corrupt_session_warning(self):
        missing = self.root / "removed-project"
        self.write_session("missing.jsonl", "missing", missing)
        current = self.write_session("state.jsonl", "state", self.project)
        corrupt = self.sessions / "corrupt.jsonl"
        corrupt.write_text('{"type":"session","id":"broken"}\n{not-json}\n')
        malformed = self.write_session(
            "malformed-line.jsonl",
            "malformed-line",
            self.project,
            ({"type": "message", "id": "ok", "message": {"role": "user", "content": "valid content"}},),
        )
        malformed.write_text(malformed.read_text() + "{not-json}\n")

        initial = self.cli("status")
        self.assertEqual(initial["sessions"], 2)
        self.assertEqual(initial["unresolved"], 1)
        self.assertTrue(any("corrupt.jsonl" in warning for warning in initial["warnings"]))

        mined = self.cli("mine")
        self.assertEqual({item["session_id"] for item in mined["sessions"]}, {"state", "malformed-line"})
        searched = self.cli("search", "valid content")
        self.assertEqual(searched["results"][0]["session_id"], "malformed-line")
        self.assertTrue(any("invalid JSONL line" in warning for warning in searched["warnings"]))
        reviewed = self.cli("mark-reviewed", "state", "--status", "reviewed")
        self.assertEqual(reviewed["status"], "reviewed")
        self.assertEqual(self.cli("status")["reviewed"], 1)
        self.assertEqual(
            [item["session_id"] for item in self.cli("mine")["sessions"]],
            ["malformed-line"],
        )
        marked = self.cli("mark-reviewed", "state", "--status", "pending", "--candidate-count", "2")
        self.assertEqual(marked["status"], "pending")
        self.assertEqual(marked["candidate_count"], 2)
        pending = self.cli("status")
        self.assertEqual(pending["pending"], 1, pending)

        current.write_text(current.read_text() + json.dumps({"type": "message", "id": "extra", "message": {"role": "user", "content": "new context"}}) + "\n")
        changed = self.cli("status")
        self.assertEqual(changed["changed"], 1)
        changed_mine = self.cli("mine")
        self.assertEqual(
            {item["session_id"] for item in changed_mine["sessions"]},
            {"state", "malformed-line"},
        )
        resolved = self.cli("mark-reviewed", "state", "--status", "resolved")
        self.assertEqual(resolved["status"], "resolved")
        self.assertEqual(self.cli("status")["resolved"], 1)

        mapped = self.cli("map-project", "missing", "--to-current")
        self.assertEqual(mapped["mapped"], str(missing))
        after_map = self.cli("status")
        self.assertEqual(after_map["sessions"], 3)
        self.assertEqual(after_map["unresolved"], 0)
        self.assertEqual(oct((self.config / "projects.json").stat().st_mode & 0o777), "0o600")

        current.unlink()
        deleted = self.cli("status")
        self.assertEqual(deleted["sessions"], 2)
        self.assertEqual(deleted["changed"], 0)


if __name__ == "__main__":
    unittest.main()
