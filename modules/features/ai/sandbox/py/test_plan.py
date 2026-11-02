"""执行计划端到端测试：用临时目录里的真实 git 仓库与 YAML 驱动 `python -m sb plan`。

运行（需要 yq、git）：nix shell nixpkgs#yq-go -c python3 test_plan.py
YAML 用 JSON 写，它是合法 YAML，yq 照常解析。
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).parent
CEILING = {
    "mount_roots": ["~/Code"],
    "network": {"allow": ["public", "dns", "host:tcp:8317"], "default_grant": ["192.168.1.5:8080"]},
}


def git(*args):
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args], check=True, capture_output=True)


class PlanTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="sb-plan-")).resolve()
        self.addCleanup(lambda: subprocess.run(["rm", "-rf", str(self.tmp)]))
        self.home = self.tmp / "home"
        self.proj = self.home / "Code" / "proj"
        self.proj.mkdir(parents=True)
        git("init", "-q", str(self.proj))
        git("-C", str(self.proj), "commit", "-q", "--allow-empty", "-m", "i")
        self.ceiling = dict(CEILING)

    def plan(self, project_cfg=None, cwd=None):
        if project_cfg is not None:
            (self.proj / ".sandbox.yaml").write_text(json.dumps(project_cfg))
        ceiling = self.tmp / "sb.yaml"
        ceiling.write_text(json.dumps(self.ceiling))
        r = subprocess.run(
            [sys.executable, "-m", "sb", "plan", str(cwd or self.proj), str(ceiling)],
            cwd=HERE,
            capture_output=True,
            text=True,
            env={**os.environ, "HOME": str(self.home)},
        )
        return r.returncode, (json.loads(r.stdout) if r.returncode == 0 else None), r.stderr.strip()

    def ok(self, project_cfg=None, **kw):
        rc, plan, err = self.plan(project_cfg, **kw)
        self.assertEqual(rc, 0, err)
        return plan

    def rejected(self, project_cfg=None, **kw):
        rc, plan, err = self.plan(project_cfg, **kw)
        self.assertEqual((rc, plan), (1, None))
        self.assertTrue(err.startswith("[-] 错误: "), err)
        return err

    def test_project_without_sandbox_yaml_gets_only_ceiling_grants(self):
        plan = self.ok()
        self.assertEqual(plan["project_root"], str(self.proj))
        self.assertEqual(plan["network"], ["192.168.1.5:8080"])
        self.assertEqual(plan["default_allow"], ["host:tcp:8317"])
        self.assertEqual((plan["imports"], plan["paths"]), ([], []))

    def test_cwd_in_subdirectory_resolves_to_repo_root(self):
        (self.proj / "a" / "b").mkdir(parents=True)
        plan = self.ok(cwd=self.proj / "a" / "b")
        self.assertEqual(plan["project_root"], str(self.proj))
        self.assertEqual(plan["cwd"], str(self.proj / "a" / "b"))

    def test_project_outside_mount_roots_is_rejected(self):
        self.ceiling["mount_roots"] = ["~/Elsewhere"]
        (self.home / "Elsewhere").mkdir()
        self.assertIn("超出沙箱能力上限", self.rejected())

    def test_worktree_common_dir_must_be_inside_mount_roots(self):
        outside = self.tmp / "outside" / "main"
        outside.mkdir(parents=True)
        git("init", "-q", str(outside))
        git("-C", str(outside), "commit", "-q", "--allow-empty", "-m", "i")
        wt = self.home / "Code" / "wt"
        git("-C", str(outside), "worktree", "add", "-q", str(wt), "-b", "wt")
        err = self.rejected(cwd=wt)
        self.assertIn("git common dir", err)
        self.assertIn("mount_roots", err)

    def test_network_merges_project_and_ceiling_grants_sorted_and_unique(self):
        plan = self.ok({"network": ["192.168.1.5:8080", "10.0.0.9:80", "10.0.0.1"]})
        self.assertEqual(plan["network"], ["10.0.0.1", "10.0.0.9:80", "192.168.1.5:8080"])

    def test_network_rejects_anything_but_ip_or_ip_port(self):
        for bad in ["host:80", "1.2.3", "1.2.3.4:abc", 8080]:
            with self.subTest(bad=bad):
                self.assertIn("只接受 IP 或 IP:端口", self.rejected({"network": [bad]}))

    def test_imports_are_staged_by_sorted_target_directory(self):
        (self.proj / "a.txt").write_text("x")
        plan = self.ok(
            {
                "imports": [
                    {"src": "a.txt", "target": "~/.zeta/a"},
                    {"src": "a.txt", "target": "~/.alpha/a"},
                    {"src": "a.txt", "target": "~/.zeta/b"},
                ]
            }
        )
        self.assertEqual([i["stage"] for i in plan["imports"]], [1, 0, 1])
        self.assertEqual([i["dir"] for i in plan["imports"]], ["~/.zeta", "~/.alpha", "~/.zeta"])
        self.assertTrue(all(i["src"] == str(self.proj / "a.txt") for i in plan["imports"]))

    def test_import_target_must_sit_in_a_subdirectory_without_dotdot(self):
        (self.proj / "a.txt").write_text("x")
        for bad in ["foo/bar", "~/x", "/x", "~/a/../b/c", "~/a/b/"]:
            with self.subTest(target=bad):
                self.assertIn("imports 的 target 必须", self.rejected({"imports": [{"src": "a.txt", "target": bad}]}))

    def test_import_needs_existing_file_src_and_a_target(self):
        (self.proj / "d").mkdir()
        self.assertIn("每项都要写 src 与 target", self.rejected({"imports": [{"target": "~/.k/a"}]}))
        self.assertIn("每项都要写 src 与 target", self.rejected({"imports": ["a.txt"]}))
        self.assertIn("导入文件不存在", self.rejected({"imports": [{"src": "d", "target": "~/.k/a"}]}))

    def test_duplicate_import_target_reports_the_first_in_sorted_order(self):
        (self.proj / "a.txt").write_text("x")
        items = [{"src": "a.txt", "target": t} for t in ["~/.z/a", "~/.z/a", "~/.b/a", "~/.b/a"]]
        self.assertIn("imports 的 target 重复: ~/.b/a", self.rejected({"imports": items}))

    def test_paths_accept_strings_ro_suffix_and_objects(self):
        for d in ["d1", "d2", "d3"]:
            (self.proj / d).mkdir()
        plan = self.ok({"paths": ["d1", "d2:ro", {"path": "d3", "readonly": True}]})
        self.assertEqual(
            plan["paths"],
            [
                {"path": str(self.proj / "d1"), "readonly": False},
                {"path": str(self.proj / "d2"), "readonly": True},
                {"path": str(self.proj / "d3"), "readonly": True},
            ],
        )

    def test_path_must_exist_and_stay_inside_mount_roots_after_following_symlinks(self):
        os.symlink("/etc", self.proj / "esc")
        self.assertIn("额外路径不存在", self.rejected({"paths": ["nope"]}))
        self.assertIn("超出能力上限", self.rejected({"paths": ["esc"]}))

    def test_invalid_default_grant_in_ceiling_is_rejected(self):
        self.ceiling["network"] = {"default_grant": ["1.2.3.4"]}
        self.assertIn("default_grant 只接受 IP:端口", self.rejected())


if __name__ == "__main__":
    unittest.main()
