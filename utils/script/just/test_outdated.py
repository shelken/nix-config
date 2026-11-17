import importlib.util
from pathlib import Path

SCRIPT = Path(__file__).with_name("outdated.py")
spec = importlib.util.spec_from_file_location("outdated", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

assert module.parse_probe("/nix/store/aaa-nixos-system-x 1794932735 no") == (
    "/nix/store/aaa-nixos-system-x",
    1794932735,
    "no",
)
assert module.parse_probe("/nix/store/bbb-darwin-system-y 1794932735 -")[2] == "-"
for bad in ("", "/nix/store/aaa 1794932735", "/nix/store/aaa 1 no extra", "/nix/store/aaa notanumber no"):
    try:
        module.parse_probe(bad)
    except ValueError:
        pass
    else:
        raise AssertionError(f"应当抛 ValueError：{bad!r}")

probe = ("/nix/store/aaa-x", 1, "no")
assert module.classify("/nix/store/aaa-x", None, probe, None) == "最新"
assert module.classify("/nix/store/zzz-x", None, probe, None) == "待部署"
assert module.classify("/nix/store/aaa-x", None, None, "超时") == "不可达"
assert module.classify(None, "error: boom", probe, None) == "求值失败"
assert module.classify(None, "error: boom", None, "超时") == "求值失败"  # 同时失败时优先报求值失败
