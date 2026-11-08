import importlib.util
from pathlib import Path

SCRIPT = Path(__file__).with_name("sync_pi_compaction.py")
spec = importlib.util.spec_from_file_location("sync_pi_compaction", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

# 向下就近：取「窗口 - 节点 >= 下限」的最大节点，预留 = 窗口 - 节点
nodes = (250_000, 400_000)
floor = 16_384
reserve = lambda window: module.reserve_for(window, nodes, floor)

assert reserve(272_000) == 22_000  # 只够 250k 节点
assert reserve(500_000) == 100_000  # 400k 与 250k 都可用，取更大的 400k
assert reserve(1_000_000) == 600_000
assert reserve(1_048_576) == 648_576
assert reserve(872_000) == 472_000
assert reserve(256_000) is None  # 256k-250k=6000 < 下限，放弃该节点，走 pi 默认
assert reserve(200_000) is None  # 比最小节点还小
assert reserve(266_384) == 16_384  # 恰好等于下限仍可用
assert reserve(400_000) == 150_000  # 400k 节点差 0 < 下限，退到 250k

# 只回填 enabledModels 里的模型，保持其顺序；其他字段原样保留
settings = {
    "enabledModels": ["p/big:high", "p/mid:high", "p/small:high", "p/offline:high"],
    "compaction": {
        "reserveTokens": 22000,
        "modelOverrides": {
            "p/stale": {"reserveTokens": 1},  # 不在 enabledModels：删除
            "p/small": {"reserveTokens": 99},  # 算法给不出值：删除
            "p/offline": {"reserveTokens": 5},  # 查不到窗口：保持原样
            "p/mid": {"reserveTokens": 1},
        },
    },
}
windows = {"p/big": 1_000_000, "p/mid": 272_000, "p/small": 128_000}
result, missing = module.apply(settings, windows, nodes, floor)

overrides = result["compaction"]["modelOverrides"]
assert list(overrides) == ["p/big", "p/mid", "p/offline"], overrides
assert overrides["p/big"] == {"reserveTokens": 600_000}
assert overrides["p/mid"] == {"reserveTokens": 22_000}
assert overrides["p/offline"] == {"reserveTokens": 5}
assert missing == ["p/offline"]
assert result["compaction"]["reserveTokens"] == 22000
assert settings["compaction"]["modelOverrides"]["p/stale"] == {"reserveTokens": 1}  # 不改入参

# 幂等
again, _ = module.apply(result, windows, nodes, floor)
assert again == result
print("ok")
