"""测试环境：临时 HOME、真实 git 项目、sb-config.json 与一个假的 msb。

假 msb 把 VM 状态存在一个 JSON 文件里，只实现 sb 用到的子命令，并把每次调用记进 calls，
让测试在没有 microsandbox 的机器上驱动完整的生命周期状态机。
"""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).parent

FAKE_MSB = r'''#!{python}
import json, os, sys
state_path = os.environ["FAKE_MSB_STATE"]
st = json.load(open(state_path))
args = sys.argv[1:]
st["calls"].append(args)
st["envs"].append({{k: os.environ.get(k) for k in ("MSB_HOME", "MSB_CONFIG_PATH")}})
st["secret_envs"].append([args[0], os.environ.get("GITHUB_TOKEN")])

def save():
    json.dump(st, open(state_path, "w"))

def labels(a):
    out = {{}}
    for i, x in enumerate(a):
        if x == "--label":
            k, v = a[i + 1].split("=", 1)
            out[k] = v
    return out

cmd = args[0]
rc = 0
if cmd == "inspect":
    vm = st["vm"]
    if vm is None:
        rc = 1
    else:
        print(json.dumps({{
            "status": vm["status"],
            "config": {{"labels": vm["labels"], "resources": vm["resources"]}},
            "active_config": {{"resources": vm["resources"]}},
        }}))
elif cmd == "volume":
    if args[1] == "inspect":
        rc = 0 if args[2] in st["volumes"] else 1
    else:
        st["volumes"].append(args[2])
elif cmd == "create":
    conf = json.load(open(args[args.index("--conf") + 1]))
    st["vm"] = {{"status": "Running", "labels": labels(args), "conf": conf,
                "resources": {{"cpus": conf["cpus"], "memory_mib": 8192}}}}
    if st["create_rc"]:
        st["vm"] = None
        rc = st["create_rc"]
elif cmd == "start":
    st["vm"]["status"] = "Running"
elif cmd == "stop":
    st["vm"]["status"] = "Stopped"
elif cmd == "rm":
    st["vm"] = None
elif cmd == "copy":
    rc = st["copy_rc"]
elif cmd == "exec":
    rest = args[args.index("--") + 1:]
    if rest[-1] == "--check-busy":
        if st["busy_rc"]:
            print("boom", file=sys.stderr)
            rc = st["busy_rc"]
        else:
            print(st["busy"])
    elif rest[1:2] == ["/fake/guest-status"]:
        for t in st["missing"]:
            print(t)
    elif rest[1:2] == ["/fake/sync-guest"]:
        rc = st["sync_rc"]
    elif rest[1:2] == ["/fake/launcher"]:
        rc = st["run_rc"]
save()
sys.exit(rc)
'''


class SbEnv:
    def __init__(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="sb-test-")).resolve()
        self.home = self.tmp / "home"
        self.project = self.home / "Code" / "proj"
        self.project.mkdir(parents=True)
        self._git("init", "-q", str(self.project))
        self._git("-C", str(self.project), "commit", "-q", "--allow-empty", "-m", "i")

        self.mise = self.tmp / "mise"
        (self.mise / "data").mkdir(parents=True)
        self.publish = self.tmp / "publish"
        (self.publish / "current").mkdir(parents=True)
        self.config_file = self.tmp / "sb-config.json"
        self.policy = self.tmp / "sb.yaml"
        self.state = self.tmp / "msb-state.json"
        self.state.write_text(
            json.dumps(
                {
                    "vm": None, "volumes": [], "calls": [], "envs": [], "secret_envs": [], "busy": 0, "busy_rc": 0, "missing": [],
                    "sync_rc": 0, "run_rc": 0, "copy_rc": 0, "create_rc": 0,
                }
            )
        )  # fmt: skip
        bindir = self.tmp / "bin"
        bindir.mkdir()
        msb = bindir / "msb"
        msb.write_text(FAKE_MSB.format(python=sys.executable))
        msb.chmod(0o755)

        self.write_config()
        self.set_policy()
        # 不继承调用者的环境：MSB_HOME、SB_* 指向真实目录，sb trust 会把批准记录写进去
        inherited = {k: os.environ[k] for k in ("LANG", "LC_ALL", "TMPDIR") if k in os.environ}
        self.env = {
            **inherited,
            "HOME": str(self.home),
            "PATH": f"{bindir}:{os.environ['PATH']}",
            "PYTHONPATH": str(HERE),
            "SB_CONFIG_FILE": str(self.config_file),
            "FAKE_MSB_STATE": str(self.state),
        }

    def write_config(self, **overrides):
        config = {
            "msb_config": str(self.tmp / "msb-config.json"), "msb_home": str(self.tmp / "msbhome"), "policy_yaml": str(self.policy),
            "publish_dir": str(self.publish), "launcher": "/fake/launcher", "guest_status": "/fake/guest-status", "guest_sync": "/fake/sync-guest",
            "sync_lock": str(self.tmp / "sync.lock"), "host_credentials": False, "host_secret_files": {},
            "guest": {"config_mount": "/run/sandbox-config", "contexts_dir": "/run/sandbox/contexts", "data_dir": "/data"},
            "mise": {"host_dir": str(self.mise), "guest_mount": "/opt/sandbox-mise"},
        }  # fmt: skip
        self.config_file.write_text(json.dumps({**config, **overrides}))

    def close(self):
        subprocess.run(["rm", "-rf", str(self.tmp)])

    @staticmethod
    def _git(*args):
        subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args], check=True, capture_output=True)

    def set_policy(self, **overrides):
        policy = {
            "image": "ubuntu", "cpus": 2, "memory": "8G", "volume": {"name": "sb-main-data", "size": "8G"},
            "mount_roots": ["~/Code"],
            "network": {"policy": "public", "allow": ["public", "dns", "host:tcp:8317"], "default_grant": ["192.168.1.5:8080"]},
        }  # fmt: skip
        policy.update(overrides)
        self.policy.write_text(json.dumps(policy))

    def set_project(self, cfg):
        (self.project / ".sandbox.yaml").write_text(json.dumps(cfg))

    def msb_state(self, **updates):
        st = json.loads(self.state.read_text())
        st.update(updates)
        self.state.write_text(json.dumps(st))
        return st

    def calls(self, name=None):
        calls = self.msb_state()["calls"]
        return [c for c in calls if name is None or c[0] == name]

    def sb(self, *args, cwd=None, **env):
        return subprocess.run(
            [sys.executable, "-P", "-m", "sb", *args],
            cwd=cwd or self.project,
            capture_output=True,
            text=True,
            env={**self.env, **env},
        )
