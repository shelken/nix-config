# 0004. 按功能内聚的 Dendritic 模块结构

日期：2026-10-23（第 4、11–13 条于同日全量迁移时补充）

## 状态

已采纳 (Accepted)。试点与全量迁移见 PR #125

## 背景与问题

同一功能的配置按配置层分散在两棵树：Homebrew、launchd、系统 defaults 在 `modules/darwin/`，用户态配置在 `home/`。新增或修改一个功能需要同时改两处，开关还要在 `hosts/<host>/default.nix` 与 `home.nix` 手动镜像（试点前有 7 个选项在两棵树各声明一次）

另有两个约束：

- 仓库没有独立运行的 Home Manager，`homeConfigurations` 从系统配置的求值结果导出（`flake.nix`），HM 可以由系统模块经 `home-manager.sharedModules` 注入
- 主机按职责分为常驻服务器、远程开发机、桌面机、主力机，部分桌面机兼做服务器，软件差异需要按职责组合表达

## 决策

1. **flake-parts + import-tree**：`flake.nix` 使用 `flake-parts.lib.mkFlake`，递归加载 `modules/{flake,features,profiles}`；路径含 `/_` 的文件不自动导入，用于数据或私有片段
2. **同名即同一功能**：功能以 `flake.modules.<类>.<名>` 发布，类为 `darwin`、`nixos`、`homeManager`。`modules/flake/features.nix` 把 `homeManager.<名>` 自动挂到同名系统模块，功能文件不写接线代码
3. **大功能拆目录**：同一个 `flake.modules.<类>.<名>` 可由多个文件分别声明并自动合并，如 `features/tools/autoinputswitch/{darwin,home}.nix`
4. **主角色链**：darwin 为 `core ⊂ tui ⊂ gui ⊂ desktop ⊂ workstation`，NixOS 为 `core ⊂ tui ⊂ gui`；每台主机只导入一个主角色。`desktop` 是日常桌面机共有的一层（容器、字体、lima 等），精简桌面机（ling）停在 `gui`。包含关系只写在系统侧，`homeManager.<角色>` 只放本层内容
5. **附加角色**：给主角色叠加一类职责，与主角色并列导入，如 `[ gui homelab ]`。附加角色不导入主角色链
6. **功能声明归属**：功能在自己的文件里声明加入哪个角色，主机不列具体功能。差异落点：
   - 某个角色的所有主机需要：加入该角色
   - 跨角色的一组主机需要：加入附加角色
   - 只有一台主机需要：主机直接导入该功能
   - 都需要但参数不同：功能声明选项，主机设值，HM 部分经 `osConfig` 读取
7. **接口放 core，实现放功能**：会被其他功能写入的选项（如 `shelken.backup.app`）必须在 core 声明，否则未导入实现的主机会因选项不存在而求值失败
8. **密钥是主机属性**：sops 模块放 core。`shelken.secrets.enable` 表示「这台主机有 age 密钥」，由主机设置。需要密钥的功能在自己文件里声明 `sops.secrets.*`，并断言 `secrets.enable`，不替主机打开该开关。系统侧镜像的同名选项删除，系统需要时读 HM 配置
9. **平台分支**：HM 部分由 darwin 与 nixos 共用。少量差异保留 `isDarwin` 判断；只在 darwin 需要的大块 HM 配置放到功能的 `darwin.nix`，经 `home-manager.sharedModules` 注入
10. **仓库内文件软链使用路径字面量**：`mylib.mkConfigLink` / `mkConfigFile` 接收 `./x` 形式的路径，文件挪动后求值即报错（`lib/default.nix`）
11. **没有主机启用的功能做成可选功能**：迁移成功能但不加入任何角色，也不保留 `enable` 开关；要用的主机在 `imports` 里加一行
12. **互斥实现用选项**：同一职责有多个互斥实现时，功能加入覆盖全部主机的角色，用 enum 选项选择实现，例如 `shelken.wm.manager = "aerospace" | "omniwm"`（默认 aerospace，mio 设 omniwm）。不拆成多个可选功能：拆开后各主机都要显式导入一个，同时导入两个也拦不住
13. **HM 配置跟随应用本体归属**：应用由系统侧某个功能安装时（如 brew cask），它的 HM 配置并入同一功能或同一角色，不按「GUI 配置」整体挂在 `gui` 上。迁移时以此修正了 orca、zed、pi 配置出现在未安装应用的主机上的问题

## 不变量

- flake-parts 不给发布的模块设 `key`，同一模块导入两次不会去重：列表选项重复，声明选项的模块直接报错。所以同一台主机上每个模块只能有一条导入路径
  - HM 侧不写角色 imports 链
  - 一个功能只加入一个角色
  - 主机不再单独导入已在其角色内的功能
  - 主机不同时导入两个互相包含的角色
- `calcUniformSchedule` 按 `hosts/` 下的目录数排定备份时段，新增 `hosts/` 目录会移动所有主机的时段。无硬件配置的求值测试机不建目录，角色直接写在主机表

## 考虑过的替代方案

- **保留两棵树，系统模块顺带写 HM**：不改构建入口，可以逐个迁移。但 nixos 与 darwin 共用的文件需要按平台判断，否则 `homebrew` 等选项不存在时报错；分层与组合仍靠开关
- **保留 `enable` 开关，用 suite 批量打开**（snowfall-lib 风格）：主机里仍是一组开关，同一职责在 suite 与主机两处管理。现有的 `suites.desktop` 已经与主机职责对不上（ling 是桌面机但未开启）
- **按 `key` 包装每个模块以自动去重**：可以放宽「一条导入路径」的约束，但每次加入角色都要多写一层包装，格式更繁杂。等出现真实的多路径需求再做

## 影响与代价

- 主机的 `imports` 一行即可表达职责组合，新增功能只改功能自己的目录
- 模块合并时，层级越深的定义越靠前。角色链改变了列表选项的顺序，Brewfile、`system-path` 的包顺序会变：`system-path` 开启 `ignoreCollisions`，同优先级时排前的包胜出，迁移时需要确认首次出现顺序或同路径文件无冲突
- 角色名与功能名共用 `flake.modules.<类>` 命名空间，功能不能命名为 `core`、`tui`、`gui`、`desktop`、`workstation`、`homelab`
- 同名挂接会为每个 HM 功能生成 `nixos.<名>` 与 `darwin.<名>`，即使该功能只适用于一个平台。只适用 darwin 的功能在 NixOS 上导入会因缺少选项而报错
