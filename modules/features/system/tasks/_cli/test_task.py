import gzip
import os
import sys
import tempfile
import unittest
import unittest.mock

sys.path.insert(0, os.path.dirname(__file__))

import task  # noqa: E402


class RunRegressionTest(unittest.TestCase):
    def _make_fake_task(self, bindir, script):
        fake = os.path.join(bindir, "task-fake")
        with open(fake, "w") as handle:
            handle.write("#!/bin/sh\n" + script)
        os.chmod(fake, 0o755)
        return fake

    def test_run_propagates_child_exit_code(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = os.path.join(tmp, "home")
            bindir = os.path.join(tmp, "bin")
            os.makedirs(home)
            os.makedirs(bindir)
            self._make_fake_task(bindir, "echo hi\nexit 3\n")
            env = {"HOME": home, "PATH": bindir + os.pathsep + os.environ["PATH"]}
            with unittest.mock.patch.dict(os.environ, env):
                code = task.main(["run", "fake"])
            self.assertEqual(code, 3)
            log = os.path.join(home, "Library", "Logs", "task-fake.log")
            self.assertTrue(os.path.isfile(log))
            with open(log) as handle:
                self.assertIn("hi", handle.read())

    def test_run_as_launchd_controls_launchd_env(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = os.path.join(tmp, "home")
            bindir = os.path.join(tmp, "bin")
            os.makedirs(home)
            os.makedirs(bindir)
            self._make_fake_task(bindir, 'echo "LAUNCHD=${SHELKEN_TASK_LAUNCHD:-unset}"\n')
            env = {
                "HOME": home,
                "PATH": bindir + os.pathsep + os.environ["PATH"],
                "SHELKEN_TASK_LAUNCHD": "1",
            }
            with unittest.mock.patch.dict(os.environ, env):
                self.assertEqual(task.main(["run", "fake"]), 0)
            log = os.path.join(home, "Library", "Logs", "task-fake.log")
            with open(log) as handle:
                self.assertEqual(handle.read().strip(), "LAUNCHD=unset")

            os.remove(log)
            env.pop("SHELKEN_TASK_LAUNCHD")
            with unittest.mock.patch.dict(os.environ, env, clear=True):
                self.assertEqual(task.main(["run", "--as-launchd", "fake"]), 0)
            with open(log) as handle:
                self.assertEqual(handle.read().strip(), "LAUNCHD=1")


ROTATED_TEXT = """[2026-11-12 03:24:46] ===== Task 'x' Started (launchd) =====
deleting '/nix/store/...'
[2026-11-12 03:24:52] ===== Task 'x' Finished (exit code: 0) =====
"""


class RotatedLogRegressionTest(unittest.TestCase):
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
