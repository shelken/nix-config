# 求值期不依赖构建：Nix 只声明结构，运行时值运行时读

日期: 2026-11-17

求值依赖构建（IFD，Import From Derivation）会让「在一台机器上求值、在另一台机器上构建」的流程失败。#335：从 mac 用 nixos-anywhere 给 x86_64 节点装机，求值机要先构建目标平台的 derivation，构建在目标机上完成，产物没有签名，拷回求值机的存储时被拒，报 catppuccin-starship 路径缺签名。用 `--option allow-import-from-derivation false` 逐台求值，全仓库有三处 IFD：catppuccin 的 starship 主题与 `palette.json`（whiskers 构建的 port）、agent 定义里解析模型角色的 `mylib.readYaml`、pi 的 `models.json` 所读的 YAML。现在仓库的约定是求值不依赖构建

## 原则

Nix 只声明结构：有哪些 agent、各自用哪个 role 名。role 对应哪个模型这类运行时值，只在运行时从 YAML 读。求值期不读任何 YAML，也不读构建产物

## 三处的处理

- **catppuccin 取源码**：starship 主题与 `palette.json` 用 `builtins.fetchTree` 取上游仓库，rev 与 hash 取自 catppuccin 自己的 `pkgs/sources.json`，不单独锁版本（见 `modules/features/system/catppuccin.nix`）
- **agent 只声明 role**：`modules/features/ai/agents/default.nix` 的 `roleOf` 是静态规则：显式 `modelRole`，其次生成的变体用 `reviewer-<后缀>`，其次是 agent 名本身。pi 的 md 只写 `role`、`tools` 与正文；omp 的 md 一律写 `model: @<role>`。omp 自己解析 `@role` 且 `task.agentModelOverrides` 优先；pi 的 `spawn-subagent` 每次派发读 `~/.omp/agent/config.yml`，按 override 或 role 解析出 model 与 thinking
- **`pi-models.json` 构建期生成**：`modules/features/ai/pi/default.nix` 在 `runCommand` 里用 yj 把 `omp/models.yml` 与 `pi/models.yml` 转 JSON，再由 `modules/features/ai/pi/models.jq` 完成合并与 omp 到 pi 的字段适配。Nix 不读这两个 YAML

## 规则

- 求值期不得读取构建产物（`import`、`readFile`、`fromJSON` 等作用于 derivation 输出），也不得读 YAML
- 需要 YAML 内容的产物放到构建期（`runCommand`）或运行时生成
- 提交前跑 `just check-ifd`（`utils/script/just/check_ifd.py`）：并行求值所有主机的 toplevel 或 system drvPath 并禁用 IFD。只有 IFD 被禁用的报错才算失败；其他求值错误（读私有 secrets 失败、测试主机缺根文件系统的断言）提示后跳过

## 考虑过的替代方案

- **#335 原方案，把 catppuccin 的 port 源码加为 flake input**：版本会和 catppuccin 漂移。`fetchTree` 直接读 catppuccin 锁定的 rev 与 hash，自动跟随
- **`dontCatppuccinBuild`**：`palette` 已经开着它，但 port 仍是 derivation，求值期读它依然是 IFD
- **catppuccin 官方缓存**：`catppuccin.nix` 为绕开 catppuccin/nix#927 用 `overrideScope` 替换了 whiskers，路径哈希与上游不同，缓存里没有
- **纯 Nix 的 YAML 解析库**：实测 milahu/nix-yaml 把行内列表 `[low, medium]` 和 `[]` 解析成字符串，不报错，数据静默出错
- **入库 JSON 镜像**：生成物进 git，要靠哈希护栏、钩子与构建配方防止与源 YAML 不同步，维护成本高于收益
- **由 Nix 生成 YAML**：omp 的 `omp config set/reset` 会写 `config.yml`，liveEdit 主机上它是指回仓库的链接，生成与回写互相覆盖
- **等官方 `builtins.fromYAML`**：NixOS/nix#7340 未合并，没有时间表
- **用 CI 跑 IFD 检查**：CI 读不到私有 secrets，读它的主机求值失败而被跳过（ADR 0009 同样跳过这类主机），实测 12 台里只覆盖 2 台，对读 secrets 的主机没有保护，已放弃。要提高覆盖需让 CI 能读 secrets，目前不值得

## 后果

- 新代码求值期不得读 YAML 或构建产物；提交前跑 `just check-ifd`
- 没有 CI 守卫：新增 IFD 只在本地 `just check-ifd` 里被发现，靠提交前自觉运行。被跳过的主机（读私有 secrets、断言失败）上的 IFD 无法在当前环境检查
- 变体 agent 的 role 是静态规则，只会得到 `reviewer-<后缀>`。在 `modelRoles` 新增角色不会自动生效，需要在 `agents/default.nix` 声明
- `spawn-subagent` 不再有 md 兜底：`config.yml` 读不到或解析不出 model 与 thinking 时直接报错，不派发
