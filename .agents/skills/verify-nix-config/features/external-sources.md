# 更新外部源

维护者修改 `nvfetcher.toml` 后，可以重新生成可复现的外部源元数据，并确认配置仍消费生成结果。

## Sub-features

- `generate`，从 `nvfetcher.toml` 生成 `_sources/`
- `build`，构建受外部源影响的 Home Manager 或系统配置

## How to get to it (user POV)

在仓库根目录运行 `nvfetcher -c nvfetcher.toml -o _sources`。检查 `_sources/generated.json` 与 `_sources/generated.nix`，再构建实际消费该源的目标。

## Driving it with nvfetcher

Preconditions: `nvfetcher.toml` 存在，网络可访问对应上游

- 生成，运行 `nvfetcher -c nvfetcher.toml -o _sources`，观察零退出码和 `_sources/` 的更新
- 验证消费，运行受影响目标的 `PROFILE=<host> just hmb` 或 `PROFILE=<host> just bd`，观察 source derivation 成功

## Gotchas

- 只修改 `nvfetcher.toml` 不会更新 Nix 实际消费的 `_sources/`
- 生成文件是受版本控制的配置输入，应与源定义一并检查
