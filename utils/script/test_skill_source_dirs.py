import importlib.util
from pathlib import Path

SCRIPT = Path(__file__).with_name("skill_source_dirs.py")
spec = importlib.util.spec_from_file_location("skill_source_dirs", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

prefixes = {"demo": "/nix/store/aaa-source", "demo-2": "/nix/store/aaa-source-2"}

# 按前缀归属；前缀相似的 input 不能互相吞掉；不属于任何 input 的路径丢弃
dirs = module.group_dirs(
    [
        "/nix/store/aaa-source/skills/a",
        "/nix/store/aaa-source/skills/b",
        "/nix/store/aaa-source-2/x",
        "/nix/store/zzz-other/skills/c",
    ],
    prefixes,
)
assert dirs == {"demo": ["skills/a", "skills/b"], "demo-2": ["x"]}, dirs


# 某台主机求值失败：跳过它，其他主机照常
def fake_nix_json(args):
    target = args[0]
    if target.endswith("#skillUpstreams"):
        return ["good", "bad"]
    if target.endswith(".bad"):
        raise RuntimeError("secrets 不可读")
    return ["/nix/store/aaa-source/skills/a"]


module.nix_json = fake_nix_json
assert module.collect_upstreams(".") == ["/nix/store/aaa-source/skills/a"]

print("ok")
