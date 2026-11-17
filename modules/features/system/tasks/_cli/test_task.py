# task CLI 纯函数单元测试：不碰真实 launchd 与日志，只验证解析与格式化
import gzip
import os
import re
import sys
import tempfile
import unittest
import unittest.mock

sys.path.insert(0, os.path.dirname(__file__))

import task  # noqa: E402


class RunExitCodeTest(unittest.TestCase):
    def test_run_propagates_child_exit_code(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = os.path.join(tmp, "home")
            bindir = os.path.join(tmp, "bin")
            os.makedirs(home)
            os.makedirs(bindir)
            fake = os.path.join(bindir, "task-fake")
            with open(fake, "w") as handle:
                handle.write("#!/bin/sh\necho hi\nexit 3\n")
            os.chmod(fake, 0o755)
            env = {"HOME": home, "PATH": bindir + os.pathsep + os.environ["PATH"]}
            with unittest.mock.patch.dict(os.environ, env):
                code = task.main(["run", "fake"])
            self.assertEqual(code, 3)
            log = os.path.join(home, "Library", "Logs", "task-fake.log")
            self.assertTrue(os.path.isfile(log))
            with open(log) as handle:
                self.assertIn("hi", handle.read())


OLD_FORMAT = """[2026-11-13 07:44:39] ===== Task 'kopia-backup' Started =====
Backing up
[2026-11-13 07:52:34] ===== Task 'kopia-backup' Finished (exit code: 0) =====
"""

NEW_FORMAT = """[2026-11-13 20:33:48] ===== Task 'kopia-backup' Started (manual) =====
Backing up
[2026-11-13 20:34:55] ===== Task 'kopia-backup' Finished (exit code: 0) =====
"""

UNFINISHED = """[2026-11-13 07:44:39] ===== Task 'kopia-backup' Started (launchd) =====
still running
"""

TWO_RUNS = """[2026-11-13 07:44:39] ===== Task 'kopia-backup' Started (launchd) =====
Backing up
[2026-11-13 07:52:34] ===== Task 'kopia-backup' Finished (exit code: 0) =====
[2026-11-13 19:44:39] ===== Task 'kopia-backup' Started (launchd) =====
gonna fail
[2026-11-13 19:52:34] ===== Task 'kopia-backup' Finished (exit code: 1) =====
"""

RUN_LINES = [
    "[2026-11-13 07:41:36] Jitter delay: 183s",
    "[2026-11-13 07:44:39] ===== Task 'kopia-backup' Started (launchd) =====",
    "Backing up",
    "[2026-11-13 07:52:34] ===== Task 'kopia-backup' Finished (exit code: 0) =====",
    "[2026-11-13 19:39:05] Jitter delay: 268s",
    "[2026-11-13 19:43:33] ===== Task 'kopia-backup' Started (launchd) =====",
    "Backing up again",
    "[2026-11-13 19:52:34] ===== Task 'kopia-backup' Finished (exit code: 0) =====",
]

ROTATED_TEXT = """[2026-11-12 03:24:46] ===== Task 'x' Started (launchd) =====
deleting '/nix/store/...'
[2026-11-12 03:24:52] ===== Task 'x' Finished (exit code: 0) =====
"""


class ParseRunsTest(unittest.TestCase):
    def test_old_format_single_run(self):
        runs = task.parse_runs(OLD_FORMAT)
        self.assertEqual(len(runs), 1)
        self.assertEqual(runs[0].code, 0)
        self.assertIsNone(runs[0].trigger)

    def test_new_format_trigger(self):
        runs = task.parse_runs(NEW_FORMAT)
        self.assertEqual(runs[0].trigger, "manual")

    def test_unfinished_run(self):
        runs = task.parse_runs(UNFINISHED)
        self.assertIsNone(runs[0].finished)
        self.assertIsNone(runs[0].code)

    def test_last_run_exit_code(self):
        runs = task.parse_runs(TWO_RUNS)
        self.assertEqual(len(runs), 2)
        self.assertEqual(runs[-1].code, 1)


class SelectRunsTest(unittest.TestCase):
    def test_last_one_starts_at_jitter(self):
        self.assertEqual(task.select_runs(RUN_LINES, 1), RUN_LINES[4:])

    def test_last_two_is_all(self):
        self.assertEqual(task.select_runs(RUN_LINES, 2), RUN_LINES)


class FormatIntervalTest(unittest.TestCase):
    def test_intervals(self):
        self.assertEqual(task.format_interval(86400), "24h")
        self.assertEqual(task.format_interval(18000), "5h")
        self.assertEqual(task.format_interval(5400), "1h30m")
        self.assertEqual(task.format_interval(90), "90s")
        self.assertEqual(task.format_interval(3600), "1h")


class FormatScheduleTest(unittest.TestCase):
    def test_calendar_list(self):
        plist = {
            "StartCalendarInterval": [
                {"Hour": 7, "Minute": 39},
                {"Hour": 19, "Minute": 39},
            ]
        }
        self.assertEqual(task.format_schedule(plist), "07:39, 19:39")

    def test_calendar_weekday(self):
        plist = {"StartCalendarInterval": {"Hour": 5, "Minute": 0, "Weekday": 0}}
        self.assertEqual(task.format_schedule(plist), "Sun 05:00")

    def test_start_interval(self):
        self.assertEqual(task.format_schedule({"StartInterval": 18000}), "every 5h")

    def test_manual(self):
        self.assertEqual(task.format_schedule({}), "manual")


class RenderTableTest(unittest.TestCase):
    ROWS = [
        {
            "name": "kopia-backup",
            "tier": "user",
            "schedule": "07:39, 19:39",
            "last_run": "11-13 20:33",
            "result": "✓",
            "loaded": "✓",
        },
        {
            "name": "nix-gc",
            "tier": "root",
            "schedule": "03:15",
            "last_run": "11-13 03:15",
            "result": "running",
            "loaded": "✗",
        },
        {
            "name": "profile-usage",
            "tier": "user",
            "schedule": "00:04, 12:04",
            "last_run": "11-13 12:05",
            "result": "✗ 1",
            "loaded": "✓",
        },
    ]

    def test_no_ansi_without_color(self):
        self.assertNotIn("\x1b", task.render_table(self.ROWS, color=False))
        self.assertIn("NAME", task.render_table(self.ROWS, color=False))

    def test_ansi_with_color(self):
        self.assertIn("\x1b", task.render_table(self.ROWS, color=True))

    def test_color_matches_plain_after_stripping(self):
        ansi = re.compile(r"\x1b\[[0-9;]*m")
        colored = task.render_table(self.ROWS, color=True)
        plain = task.render_table(self.ROWS, color=False)
        self.assertEqual(ansi.sub("", colored), plain)


class SelectLogLinesTest(unittest.TestCase):
    def test_last_run(self):
        self.assertEqual(task.select_log_lines(RUN_LINES, 1, False), RUN_LINES[4:])

    def test_all(self):
        self.assertEqual(task.select_log_lines(RUN_LINES, 1, True), RUN_LINES)

    def test_fallback_last_50(self):
        lines = [f"line {index}" for index in range(120)]
        self.assertEqual(task.select_log_lines(lines, 1, False), lines[-50:])


class RotatedLogTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.mkdtemp()
        self.path = os.path.join(self.directory, "task-x.log")
        open(self.path, "w").close()
        with gzip.open(self.path + ".0.gz", "wt") as handle:
            handle.write(ROTATED_TEXT)

    def test_falls_back_to_rotated(self):
        run = task.latest_run(self.path)
        self.assertIsNotNone(run)
        self.assertEqual(run.start, "2026-11-12 03:24:46")
        self.assertEqual(run.code, 0)

    def test_current_log_wins(self):
        with open(self.path, "w") as handle:
            handle.write(NEW_FORMAT)
        run = task.latest_run(self.path)
        self.assertEqual(run.start, "2026-11-13 20:33:48")

    def test_large_run_output(self):
        with open(self.path, "w") as handle:
            handle.write("[2026-11-13 01:00:00] ===== Task 'x' Started (launchd) =====\n")
            handle.write("x" * 300000 + "\n")
            handle.write("[2026-11-13 01:05:00] ===== Task 'x' Finished (exit code: 3) =====\n")
        run = task.latest_run(self.path)
        self.assertIsNotNone(run)
        self.assertEqual(run.start, "2026-11-13 01:00:00")
        self.assertEqual(run.code, 3)


if __name__ == "__main__":
    unittest.main()
