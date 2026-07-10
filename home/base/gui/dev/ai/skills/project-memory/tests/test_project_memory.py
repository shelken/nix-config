#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import tempfile
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

    def cli(self, *args, expect=0):
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
        if expect:
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
