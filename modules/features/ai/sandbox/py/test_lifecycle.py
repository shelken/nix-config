"""主 VM 生命周期与授权流程测试：真实的 `python -m sb`，假的 msb（见 testenv.py）。"""

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
        syncs = [c for c in self.e.calls("exec") if "/fake/sync-guest" in c]
        self.assertEqual(len(syncs), 1)
        self.assertIn("创建并启动成功", r.stderr)

    def test_vm_is_created_with_the_real_mise_path_not_the_fingerprint_placeholder(self):
        self.e.sb("up")
        mounts = self.e.msb_state()["vm"]["conf"]["mounts"]
        self.assertIn(f"{self.e.mise.resolve()}:/opt/sandbox-mise:rw", mounts)
        self.assertIn(f"{self.e.publish.resolve()}:/run/sandbox-config:ro,stat-virt=relaxed", mounts)
        self.assertIn({"named": "sb-main-data", "target": "/data"}, mounts)
        self.assertFalse([m for m in mounts if "__SB_MISE_HOST__" in str(m)])

    def test_up_without_a_published_config_or_mise_dir_explains_what_to_run(self):
        (self.e.publish / "current").rmdir()
        r = self.e.sb("up")
        self.assertEqual(r.returncode, 1)
        self.assertIn("沙箱配置尚未发布", r.stderr)
        self.assertEqual(self.e.calls("create"), [])
        (self.e.publish / "current").mkdir()
        self.e.write_config(mise={"host_dir": str(self.e.tmp / "missing"), "guest_mount": "/opt/sandbox-mise"})
        self.assertIn("共用 mise 目录不存在", self.e.sb("up").stderr)

    def test_a_sb_yaml_field_of_the_wrong_type_is_an_error(self):
        for key, bad in [("cpus", "4"), ("memory", 8), ("image", None), ("network", "public"), ("volume", {"name": "v"})]:
            with self.subTest(key=key):
                self.e.set_policy(**{key: bad})
                r = self.e.sb("up")
                self.assertEqual(r.returncode, 1, r.stderr)
                self.assertIn(f"{key}", r.stderr)
                self.assertEqual(self.e.calls("create"), [])

    def test_a_secret_without_an_allow_target_is_rejected_before_msb_sees_it(self):
        self.e.set_policy(secrets={"K": {"passthrough": ["*"]}})
        r = self.e.sb("up")
        self.assertEqual(r.returncode, 1)
        self.assertIn("secrets.K 至少要有一个 allow 目标", r.stderr)
        self.assertEqual(self.e.calls("create"), [])

    def test_up_again_reuses_vm_without_create_or_sync(self):
        self.e.sb("up")
        before = len(self.e.calls())
        r = self.e.sb("up")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("复用现有 VM", r.stderr)
        changing = {"create", "start", "stop", "rm", "exec"}
        after = self.e.calls()[before:]
        self.assertEqual([c for c in after if c[0] in changing or c[:2] == ["volume", "create"]], [])

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
        (moved / "data").mkdir(parents=True)
        self.e.write_config(mise={"host_dir": str(moved), "guest_mount": "/opt/sandbox-mise"})
        r = self.e.sb("up")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("复用现有 VM", r.stderr)
        self.assertEqual(len(self.e.calls("create")), 1)

    def test_secrets_and_mount_roots_are_part_of_the_ceiling(self):
        self.e.sb("up")
        for change in ({"secrets": {"K": {"allow": ["example.com"]}}}, {"mount_roots": ["~/Code", "~/Other"]}):
            with self.subTest(change=change):
                old = self.vm_fp()
                self.e.set_policy(**change)
                r = self.e.sb("up")
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertNotEqual(self.vm_fp(), old)

    def test_idle_timeout_reaches_msb_in_the_create_conf(self):
        self.e.set_policy(idle_timeout="5m")
        self.e.sb("up")
        self.assertEqual(self.e.msb_state()["vm"]["conf"]["idle_timeout"], "5m")

    def test_without_idle_timeout_the_vm_never_stops_by_itself(self):
        self.e.sb("up")
        self.assertNotIn("idle_timeout", self.e.msb_state()["vm"]["conf"])

    def test_idle_timeout_is_part_of_the_ceiling_because_msb_applies_it_only_at_creation(self):
        self.e.sb("up")
        old = self.vm_fp()
        self.e.set_policy(idle_timeout="5m")
        r = self.e.sb("up")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("正在重建", r.stderr)
        self.assertNotEqual(self.vm_fp(), old)
        self.assertEqual(self.e.msb_state()["vm"]["conf"]["idle_timeout"], "5m")

    def test_changing_idle_timeout_while_busy_refuses_like_any_ceiling_change(self):
        self.e.set_policy(idle_timeout="5m")
        self.e.sb("up")
        self.e.msb_state(busy=1)
        self.e.set_policy(idle_timeout="10m")
        r = self.e.sb("up")
        self.assertEqual(r.returncode, 1)
        self.assertIn("能力上限已变", r.stderr)
        self.assertEqual(self.e.calls("rm"), [])

    def test_an_idle_timeout_of_the_wrong_type_is_an_error(self):
        for bad in (300, True, ["5m"]):
            with self.subTest(bad=bad):
                self.e.set_policy(idle_timeout=bad)
                r = self.e.sb("up")
                self.assertEqual(r.returncode, 1, r.stderr)
                self.assertIn("idle_timeout", r.stderr)
                self.assertEqual(self.e.calls("create"), [])

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

    def test_status_says_unknown_when_the_current_ceiling_cannot_be_computed(self):
        self.e.sb("up")
        (self.e.publish / "current").rmdir()
        out = self.e.sb("status").stdout
        self.assertIn("上限一致: unknown", out)
        self.assertIn("沙箱配置尚未发布", out)

    def test_sync_starts_a_stopped_vm(self):
        self.e.sb("up")
        self.e.sb("down")
        r = self.e.sb("sync")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.e.msb_state()["vm"]["status"], "Running")
        self.assertEqual(len([c for c in self.e.calls("exec") if "/fake/sync-guest" in c]), 2)

    def test_sync_rejects_arguments(self):
        r = self.e.sb("sync", "--force")
        self.assertEqual(r.returncode, 1)
        self.assertIn("sb sync 不接受参数", r.stderr)

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
        execs = self.e.calls("exec")
        stage_dir = self.e.calls("copy")[0][2].split(":")[1].split("/imports/")[0]
        self.assertIn(["exec", "sb-main", "--", "rm", "-rf", stage_dir], execs)
        self.assertFalse(any("/fake/launcher" in c and "--check-busy" not in c for c in execs))

    def test_every_msb_call_gets_the_resolved_state_location_even_without_it_in_the_caller_env(self):
        (self.e.project / "kube.yaml").write_text("x")
        self.e.set_project({"imports": [{"src": "kube.yaml", "target": "~/.kube/config"}]})
        self.e.sb("trust")
        self.e.msb_state(copy_rc=1)  # 失败路径会经过暂存目录回收那次 msb 调用
        self.assertNotIn("MSB_HOME", self.e.env)
        self.e.sb("run", "true")
        envs = self.e.msb_state()["envs"]
        self.assertTrue(any(c[:2] == ["exec", "sb-main"] and "rm" in c for c in self.e.calls()))
        want = {"MSB_HOME": str(self.e.tmp / "msbhome"), "MSB_CONFIG_PATH": str(self.e.tmp / "msb-config.json")}
        self.assertEqual([e for e in envs if e != want], [])


if __name__ == "__main__":
    unittest.main()
