import importlib.util
from pathlib import Path

SCRIPT = Path(__file__).with_name("sync_pi_compaction.py")
spec = importlib.util.spec_from_file_location("sync_pi_compaction", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

nodes = (250_000, 300_000)
floor = 16_384
reserve = lambda window: module.reserve_for(window, nodes, floor)

assert reserve(272_000) == 22_000
assert reserve(500_000) == 200_000
assert reserve(1_000_000) == 700_000
assert reserve(1_048_576) == 748_576
assert reserve(872_000) == 572_000
assert reserve(256_000) is None
assert reserve(200_000) is None
assert reserve(266_384) == 16_384
assert reserve(300_000) == 50_000

settings = {
    "enabledModels": ["p/big:high", "p/mid:high", "p/small:high", "p/offline:high"],
    "compaction": {
        "reserveTokens": 22000,
        "modelOverrides": {
            "p/stale": {"reserveTokens": 1},
            "p/small": {"reserveTokens": 99},
            "p/offline": {"reserveTokens": 5},
            "p/mid": {"reserveTokens": 1},
        },
    },
}
windows = {"p/big": 1_000_000, "p/mid": 272_000, "p/small": 128_000}
result, missing = module.apply(settings, windows, nodes, floor)

overrides = result["compaction"]["modelOverrides"]
assert list(overrides) == ["p/big", "p/mid", "p/offline"], overrides
assert overrides["p/big"] == {"reserveTokens": 700_000}
assert overrides["p/mid"] == {"reserveTokens": 22_000}
assert overrides["p/offline"] == {"reserveTokens": 5}
assert missing == ["p/offline"]
assert result["compaction"]["reserveTokens"] == 22000
assert settings["compaction"]["modelOverrides"]["p/stale"] == {"reserveTokens": 1}

again, _ = module.apply(result, windows, nodes, floor)
assert again == result
assert module.model_keys({"enabledModels": ["a/b:high", "a/b:low", "c/d:medium"]}) == {"a/b", "c/d"}
print("ok")
