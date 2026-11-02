"""主 VM 生命周期与授权流程测试：真实的 `python -m sb`，假的 msb（见 testenv.py）。

运行（需要 yq、git）：nix shell nixpkgs#yq-go -c python3 test_lifecycle.py
"""

import json
import unittest

from testenv import SbEnv


class LifecycleTest(unittest.TestCase):
    def setUp(self):
        self.e = SbEnv()
        self.addCleanup(self.e.close)

    def vm_fp(self):
        return self.e.msb_state()["vm"]["labels"]["ceiling_fingerprint"]

    def test_first_up_creates_volume_and_vm_then_syncs_once(self):
        r = self.e.sb("up")
        self.assertEqual(r.returncode, 0, r.stderr)
        st = self.e.msb_state()
        self.assertEqual(st["volumes"], ["sb-main-data"])
        self.assertEqual(st["vm"]["conf"]["cpus"], 2)
        self.assertEqual(len(self.e.calls("create")), 1)
        syncs = [c for c in self.e.calls("exec") if "sync-guest.sh" in " ".join(c)]
        self.assertEqual(len(syncs), 1)
        self.assertIn("创建并启动成功", r.stderr)

    def test_up_again_reuses_vm_without_create_or_sync(self):
        self.e.sb("up")
        before = len(self.e.calls())
        r = self.e.sb("up")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("复用现有 VM", r.stderr)
        self.assertEqual([c[0] for c in self.e.calls()[before:]], ["volume", "inspect"])

    def test_up_starts_a_stopped_vm_with_unchanged_ceiling(self):
        self.e.sb("up")
        self.e.sb("down")
        r = self.e.sb("up")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(self.e.calls("create")), 1)
        self.assertEqual(self.e.msb_state()["vm"]["status"], "Running")

    def test_ceiling_change_rebuilds_idle_vm_and_keeps_the_volume(self):
        self.e.sb("up")
        old = self.vm_fp()
        self.e.set_policy(cpus=3)
        r = self.e.sb("up")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("正在重建 (保留数据盘 sb-main-data)", r.stderr)
        self.assertNotEqual(self.vm_fp(), old)
        self.assertEqual(self.e.msb_state()["vm"]["conf"]["cpus"], 3)
        self.assertEqual(self.e.msb_state()["volumes"], ["sb-main-data"])

    def test_ceiling_change_while_busy_refuses_and_touches_nothing(self):
        self.e.sb("up")
        old = self.vm_fp()
        self.e.msb_state(busy=2)
        self.e.set_policy(cpus=3)
        r = self.e.sb("up")
        self.assertEqual(r.returncode, 1)
        self.assertIn("能力上限已变，主 VM 有 2 个上下文在运行", r.stderr)
        self.assertEqual((self.e.calls("rm"), self.e.calls("stop")), ([], []))
        self.assertEqual(self.vm_fp(), old)

    def test_unreadable_busy_count_blocks_rebuild(self):
        self.e.sb("up")
        self.e.msb_state(busy_rc=3)
        self.e.set_policy(cpus=3)
        r = self.e.sb("up")
        self.assertEqual(r.returncode, 1)
        self.assertIn("无法确认主 VM sb-main 是否有上下文在运行，本次不重建", r.stderr)
        self.assertEqual(self.e.calls("rm"), [])

    def test_mise_host_path_does_not_change_the_ceiling_fingerprint(self):
        self.e.sb("up")
        moved = self.e.tmp / "elsewhere"
        r = self.e.sb("up", SB_MISE_HOST_DIR=str(moved))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("复用现有 VM", r.stderr)
        self.assertEqual(len(self.e.calls("create")), 1)

    def test_secrets_and_mount_roots_are_part_of_the_ceiling(self):
        self.e.sb("up")
        old = self.vm_fp()
        self.e.set_policy(secrets={"K": {"value": "v"}})
        self.e.sb("up")
        self.assertNotEqual(self.vm_fp(), old)

    def test_rm_refuses_while_busy_unless_forced(self):
        self.e.sb("up")
        self.e.msb_state(busy=1)
        r = self.e.sb("rm")
        self.assertEqual(r.returncode, 1)
        self.assertIn("有 1 个上下文在运行，拒绝删除", r.stderr)
        self.assertIsNotNone(self.e.msb_state()["vm"])
        self.assertEqual(self.e.sb("rm", "--force").returncode, 0)
        self.assertIsNone(self.e.msb_state()["vm"])

    def test_status_reports_each_vm_state(self):
        out = self.e.sb("status").stdout
        self.assertIn("VM 状态: Not created", out)
        self.assertIn("上限一致: not_created", out)
        self.assertIn("缺失工具: -", out)
        self.e.sb("up")
        self.e.msb_state(busy=2, missing=["bun", "gh"])
        out = self.e.sb("status").stdout
        self.assertIn("VM 状态: Running", out)
        self.assertIn("VM 规格: cpus=2, memory=8G", out)
        self.assertIn("上限一致: consistent", out)
        self.assertIn("运行状态: busy (2)", out)
        self.assertIn("缺失工具: bun, gh", out)
        self.e.set_policy(cpus=5)
        self.assertIn("上限一致: inconsistent", self.e.sb("status").stdout)

    def test_sync_starts_a_stopped_vm_and_passes_arguments_through(self):
        self.e.sb("up")
        self.e.sb("down")
        r = self.e.sb("sync", "--force")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.e.msb_state()["vm"]["status"], "Running")
        sync_call = [c for c in self.e.calls("exec") if "sync-guest.sh" in " ".join(c)][-1]
        self.assertEqual(sync_call[-1], "--force")

    def test_sync_failure_exit_code_is_returned(self):
        self.e.sb("up")
        self.e.msb_state(sync_rc=7)
        self.assertEqual(self.e.sb("sync").returncode, 7)

    def test_failed_vm_creation_is_reported_not_waited_out(self):
        self.e.msb_state(create_rc=9)
        r = self.e.sb("up")
        self.assertEqual(r.returncode, 1)
        self.assertIn("msb create 失败 (退出码 9)", r.stderr)


class RunTest(unittest.TestCase):
    def setUp(self):
        self.e = SbEnv()
        self.addCleanup(self.e.close)

    def launcher_call(self):
        return [c for c in self.e.calls("exec") if "/fake/launcher" in c and "--check-busy" not in c][-1]

    def test_run_hands_context_id_plan_and_command_to_the_launcher(self):
        r = self.e.sb("run", "git", "status")
        self.assertEqual(r.returncode, 0, r.stderr)
        call = self.launcher_call()
        ctx_id, plan_json, cwd, *cmd = call[call.index("/fake/launcher") + 1 :]
        self.assertRegex(ctx_id, r"^ctx_\d+_\d+$")
        self.assertEqual(json.loads(plan_json)["project_root"], str(self.e.project))
        self.assertEqual((cwd, cmd), (str(self.e.project), ["git", "status"]))

    def test_run_returns_the_command_exit_code(self):
        self.e.sb("up")
        self.e.msb_state(run_rc=42)
        self.assertEqual(self.e.sb("run", "false").returncode, 42)

    def test_run_requires_a_command(self):
        r = self.e.sb("run")
        self.assertEqual(r.returncode, 1)
        self.assertIn("sb run 需要提供待执行的命令", r.stderr)

    def test_shell_is_an_interactive_bash_run(self):
        self.assertEqual(self.e.sb("shell").returncode, 0)
        call = self.launcher_call()
        self.assertEqual(call[call.index("/fake/launcher") + 4 :], ["bash"])

    def test_unapproved_project_config_blocks_run_until_trusted(self):
        self.e.set_project({"network": ["10.0.0.1:80"]})
        r = self.e.sb("run", "true")
        self.assertEqual(r.returncode, 1)
        self.assertIn("未批准，或批准后已变更", r.stderr)
        self.assertEqual(self.e.calls("create"), [])
        self.assertIn("批准状态: 未批准", self.e.sb("plan").stdout)

        self.assertEqual(self.e.sb("trust").returncode, 0)
        self.assertIn("批准状态: 已批准", self.e.sb("plan").stdout)
        self.assertEqual(self.e.sb("run", "true").returncode, 0)

    def test_approval_survives_reformatting_but_not_a_content_change(self):
        self.e.set_project({"network": ["10.0.0.1:80"]})
        self.e.sb("trust")
        (self.e.project / ".sandbox.yaml").write_text('{\n  "network": [ "10.0.0.1:80" ]\n}\n')
        self.assertEqual(self.e.sb("run", "true").returncode, 0)
        self.e.set_project({"network": ["10.0.0.1:8080"]})
        self.assertEqual(self.e.sb("run", "true").returncode, 1)

    def test_trust_without_sandbox_yaml_is_a_noop(self):
        r = self.e.sb("trust")
        self.assertEqual(r.returncode, 0)
        self.assertIn("不需要批准", r.stdout)

    def test_imports_are_copied_into_a_stage_dir_before_the_launcher_runs(self):
        (self.e.project / "kube.yaml").write_text("x")
        self.e.set_project({"imports": [{"src": "kube.yaml", "target": "~/.kube/config"}]})
        self.e.sb("trust")
        r = self.e.sb("run", "true")
        self.assertEqual(r.returncode, 0, r.stderr)
        copy = self.e.calls("copy")[0]
        self.assertEqual(copy[1], str(self.e.project / "kube.yaml"))
        self.assertRegex(copy[2], r"^sb-main:/run/sandbox/contexts/ctx_\d+_\d+/imports/0/config$")
        names = [("launcher" if "/fake/launcher" in c else c[0]) for c in self.e.calls() if c[0] in ("copy", "exec")]
        self.assertLess(names.index("copy"), names.index("launcher"))

    def test_failed_import_copy_removes_the_stage_dir_and_skips_the_launcher(self):
        (self.e.project / "kube.yaml").write_text("x")
        self.e.set_project({"imports": [{"src": "kube.yaml", "target": "~/.kube/config"}]})
        self.e.sb("trust")
        self.e.msb_state(copy_rc=1)
        r = self.e.sb("run", "true")
        self.assertNotEqual(r.returncode, 0)
        execs = [c for c in self.e.calls("exec")]
        self.assertTrue(any(c[-2:-1] == ["-rf"] or "rm" in c for c in execs), execs)
        self.assertFalse(any("/fake/launcher" in c and "--check-busy" not in c for c in execs))


if __name__ == "__main__":
    unittest.main()
