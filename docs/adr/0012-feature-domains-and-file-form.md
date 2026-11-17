# 功能按领域分类，文件形式按有无资源决定

日期: 2026-11-18

ADR 0004 规定一个功能一处，但 #125 迁移时不少旧模块整块搬进了 `darwin/`、`nixos/`、`home/` 这类按平台分的目录，`gui/`、`tools/` 则按角色或「杂项」分类，同一个功能因此散在两三处：nix GC 的 NixOS、darwin 两层分在两个目录，用户层缺失也没人发现。现在 `modules/features/` 的一级目录只按功能领域划分（nix、system、shell、cli、dev、editor、terminal、virt、desktop、input、network、secrets、backup、homelab、media、browser、social、write、ai），一个功能的 nixos、darwin、HM 三端写在同一个文件里。整理过程见 #356

## 规则

- **一级目录是领域**：不按平台（darwin、nixos、home），不按角色（gui），不设杂项目录（tools）；只在某个平台存在的功能照样放进所属领域，例如 macOS defaults 在 `system/macos/`
- **文件形式按有无资源决定**：
  - 有非 nix 文件（脚本、配置、模板、图标）时用 `<名>/default.nix`，资源放在同一目录
  - 没有资源时用 `<名>.nix`，配置直接写在 nix 里
  - 三端写在同一个文件，不按类拆成 `darwin.nix` 与 `home.nix`；`default.nix` 繁杂时才拆出 `_` 开头的私有片段
- **模块名即文件名**：`<名>.nix` 与 `<名>/default.nix` 发布的 `flake.modules.<类>.<名>` 用同一个名字；一个文件发布多个模块时，主模块用文件名。`flake.modules.<类>` 不按领域分命名空间，文件名要全局唯一且离开目录也能看懂，用 `nix-settings`、`system-packages`，不用 `settings`、`packages`
- **领域聚合模块例外**：与一级目录同名的模块（如 `ai`，ADR 0008 的 agent 运行时）可由该领域下多个文件共同写入，这些文件不必再发布与文件名同名的模块；合成一个文件会超过 500 行，按文件分开才看得清各部分
- **不写转发壳**：只把功能挂进角色、自己不定义模块的文件不单独存在，挂接写在功能本身
- **按角色打包的工具集要拆开**：每个工具归入所属领域的功能，并保留原来的角色与平台，不借拆分扩大安装范围

## 考虑过的替代方案

- **一律用 `<名>/default.nix`**：形式统一，但约 80 个只有几行的功能都要多一层目录
- **保留平台目录，只把重复的功能合并**：改动小，但新功能仍要先决定放平台目录还是领域目录，问题会再次出现
- **一个功能按类拆成 `darwin.nix` 与 `home.nix`**：靠同名挂接已能工作，但读一个功能要打开多个文件，一端缺失时也不显眼

## 后果

- 领域清单与「不按平台拆文件」由 pre-commit 钩子 `feature-domains`、`feature-platform-split` 检查，新增领域要同时改本 ADR 与钩子
- 无资源的单文件目录、转发壳、模块名与文件名不一致由 `feature-layout` 钩子（`lint/feature-layout.py`）检查；入口只引一个 `_` 片段是否算「繁杂才拆」靠评审判断，不做自动检查
- 移动或合并文件不改变求值结果；整理时以全部主机 toplevel 的 drvPath 不变作为验证标准，拆分工具集若改变了安装范围要逐项列出
- `docs/user-guide/02-features.md` 中「功能较复杂时可组织为目录」改为本 ADR 的资源规则；`docs/agents/software-config.md` 的样本改为单文件功能
