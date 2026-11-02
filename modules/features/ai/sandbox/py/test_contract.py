"""host → guest 契约测试：真实的 `sb plan --json` 产出 Plan，交给 guest/plan.sh 的 parse_plan 解析，
每个字段两边必须一致。改 Plan 字段而没同步 plan.sh，这里会失败。

运行（需要 bash ≥ 4、jq、yq、git）：
  nix shell nixpkgs#bash nixpkgs#jq nixpkgs#yq-go -c python3 -m unittest test_contract
"""

import json
import subprocess
import unittest
from pathlib import Path

from testenv import SbEnv

PLAN_SH = Path(__file__).parent.parent / "guest" / "plan.sh"

# 每个变量一行 KEY=值，数组每项一行；空数组不输出，用来确认 set -u 下空数组不报 unbound
DUMP = r"""
set -euo pipefail
source "$1"
parse_plan "$2"
printf 'ROOT=%s\n' "$PLAN_PROJECT_ROOT"
printf 'GCD=%s\n' "$PLAN_GIT_COMMON_DIR"
for x in "${PLAN_DEFAULT_ALLOW[@]}"; do printf 'ALLOW=%s\n' "$x"; done
for x in "${PLAN_NETWORK[@]}"; do printf 'NET=%s\n' "$x"; done
for x in "${PLAN_IMPORT_STAGES[@]}"; do printf 'IMP=%s\n' "$x"; done
for x in "${PLAN_PATHS[@]}"; do printf 'PATH=%s\n' "$x"; done
"""


def guest_parse(plan_json: str) -> dict[str, list[str]]:
    r = subprocess.run(["bash", "-c", DUMP, "x", str(PLAN_SH), plan_json], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    out: dict[str, list[str]] = {}
    for line in r.stdout.splitlines():
        k, _, v = line.partition("=")
        out.setdefault(k, []).append(v)
    return out


class ContractTest(unittest.TestCase):
    def setUp(self):
        self.e = SbEnv()
        self.addCleanup(self.e.close)

    def host_plan(self) -> dict:
        r = self.e.sb("plan", "--json")
        self.assertEqual(r.returncode, 0, r.stderr)
        return json.loads(r.stdout)

    def test_guest_reads_every_field_the_host_writes(self):
        (self.e.project / "a.txt").write_text("x")
        for d in ["rw", "ro"]:
            (self.e.project / d).mkdir()
        self.e.set_project(
            {
                "imports": [
                    {"src": "a.txt", "target": "~/.zeta/a"},
                    {"src": "a.txt", "target": "~/.alpha/a"},
                    {"src": "a.txt", "target": "~/.zeta/b"},
                ],
                "network": ["10.0.0.9:80", "10.0.0.1"],
                "paths": ["rw", "ro:ro"],
            }
        )
        plan = self.host_plan()
        got = guest_parse(json.dumps(plan))

        self.assertEqual(got["ROOT"], [plan["project_root"]])
        self.assertEqual(got["GCD"], [plan["git_common_dir"]])
        self.assertEqual(got["ALLOW"], plan["default_allow"])
        self.assertEqual(got["NET"], plan["network"])
        self.assertEqual(got["IMP"], [f"{s}\t{d}" for s, d in sorted({(i["stage"], i["dir"]) for i in plan["imports"]})])
        self.assertEqual(got["PATH"], [f"{p['path']}\t{str(p['readonly']).lower()}" for p in plan["paths"]])
        # 上面的夹具要真的覆盖到每种字段，避免空对空的假通过
        self.assertTrue(all(plan[k] for k in ("imports", "network", "paths", "default_allow", "git_common_dir")))

    def test_empty_plan_leaves_empty_arrays_not_unbound_variables(self):
        got = guest_parse(json.dumps(self.host_plan() | {"imports": [], "network": [], "paths": [], "default_allow": []}))
        self.assertEqual(set(got), {"ROOT", "GCD"})

    def test_malformed_plan_fails_before_anything_is_allocated(self):
        r = subprocess.run(["bash", "-c", DUMP, "x", str(PLAN_SH), "not json"], capture_output=True, text=True)
        self.assertNotEqual(r.returncode, 0)


if __name__ == "__main__":
    unittest.main()
