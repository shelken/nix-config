# 功能按领域分类，文件形式按有无资源决定

日期: 2026-11-18

ADR 0004 规定一个功能一处，但 #125 迁移时不少旧模块整块搬进了 `darwin/`、`nixos/`、`home/` 这类按平台分的目录，`gui/`、`tools/` 按角色或杂项分类，同一个功能散在两三处。现在 `modules/features/` 的一级目录只按功能领域划分，整理过程见 #356

## 规则

- 一级目录 MUST 是领域：nix、system、shell、cli、dev、editor、terminal、virt、desktop、input、network、secrets、backup、homelab、media、browser、social、write、ai；MUST NOT 按平台（darwin、nixos、home）、按角色（gui）或设杂项目录（tools）；只在某个平台存在的功能照样放进所属领域（如 macOS defaults 在 `system/macos/`）；新增领域 MUST 同时改本 ADR 与 `feature-domains` 钩子
- 文件形式按有无资源决定：有非 nix 文件（脚本、配置、模板、图标）MUST 用 `<名>/default.nix` 且资源放在同一目录；没有资源 MUST 用 `<名>.nix`
- 三端 MUST 写在同一个文件，MUST NOT 按类拆成 `darwin.nix` 与 `home.nix`；`default.nix` 繁杂时 SHOULD 拆出 `_` 开头的私有片段，是否繁杂靠评审判断
- 模块名即文件名：`<名>.nix` 与 `<名>/default.nix` 发布的模块 MUST 用同一个名字；一个文件发布多个模块时主模块 MUST 用文件名；文件名 MUST 全局唯一且离开目录也能看懂，用 `nix-settings`、`system-packages`，不用 `settings`、`packages`
- 领域聚合模块例外：与一级目录同名的模块（如 `ai`，ADR 0008 的 agent 运行时）MAY 由该领域下多个文件共同写入，这些文件 MUST NOT 再发布与文件名同名的模块；合成一个文件会超过约 500 行时才适用
- MUST NOT 写转发壳：只把功能挂进角色、自己不定义模块的文件不存在，挂接写在功能本身
- 按角色打包的工具集 MUST 拆开，每个工具归入所属领域的功能并保留原来的角色与平台，MUST NOT 借拆分扩大安装范围

## 考虑过的替代方案

- 一律用 `<名>/default.nix`：约 80 个只有几行的功能都要多一层目录
- 保留平台目录只合并重复功能：新功能仍要先决定放平台目录还是领域目录
- 一个功能按类拆 `darwin.nix` 与 `home.nix`：读一个功能要打开多个文件，一端缺失时不显眼

## 后果

- 领域清单与「不按平台拆文件」由 pre-commit 钩子 `feature-domains`、`feature-platform-split` 检查；无资源目录、转发壳、模块名一致性由 `feature-layout` 钩子（`lint/feature-layout.py`）检查
- 移动或合并文件不改变求值结果，整理时以全部主机 toplevel 的 drvPath 不变为验证标准，拆分工具集若改变安装范围 MUST 逐项列出
