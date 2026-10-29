# 按功能内聚的 Dendritic 模块结构

日期: 2026-10-23

同一功能的配置按层分散在 `modules/darwin/` 与 `home/` 两棵树里，改一个功能要改两处，开关还要在主机配置里手动镜像（试点前有 7 个选项在两棵树各声明一次）。现在用 flake-parts 加 import-tree：一个功能一个目录，以 `flake.modules.<类>.<名>` 发布，类为 `darwin`、`nixos`、`homeManager`；`homeManager.<名>` 自动挂到同名系统模块，功能文件不写接线代码。功能自己声明加入哪个角色，主机只导入角色。仓库没有独立运行的 Home Manager，`homeConfigurations` 从系统配置的求值结果导出，所以 HM 只能由系统模块经 `home-manager.sharedModules` 注入。试点与全量迁移见 PR #125

## 规则

- **角色链**：darwin 为 `core ⊂ tui ⊂ gui ⊂ desktop ⊂ workstation`，NixOS 为 `core ⊂ tui ⊂ gui`，每台主机只导入一个主角色；包含关系只写在系统侧，`homeManager.<角色>` 只放本层内容
- **附加角色**（如 `homelab`）：与主角色并列导入，不导入主角色链
- **差异落点**：某个角色的所有主机需要，加入该角色；跨角色的一组主机需要，加入附加角色；只有一台主机需要，主机直接导入；都需要但参数不同，功能声明选项、主机设值，HM 部分经 `osConfig` 读取
- **没有主机启用的功能**做成可选功能：不加入任何角色，不保留 `enable` 开关，要用的主机在 `imports` 里声明导入
- **互斥实现**采用 enum 选项（如 `shelken.wm.manager`），不拆成多个可选功能，避免各主机重复声明或同时导入多项冲突
- **接口放 core，实现放功能**：会被其他功能写入的选项必须在 core 声明，否则未导入实现的主机会因选项缺失求值失败
- **密钥是主机属性**：sops 模块放 core，`shelken.secrets.enable` 由主机设置；需要密钥的功能声明 `sops.secrets.*` 并断言，不替主机默认打开
- **HM 配置跟随应用本体归属**：应用由系统侧安装时（如 brew cask），其 HM 配置并入同一功能或角色，不整体挂在 `gui` 上
- **仓库内文件软链用路径字面量**：`mylib.mkConfigLink`、`mkConfigFile` 接收 `./x`，文件挪动后求值即报错
- 路径含 `/_` 的文件不被自动导入，用于存放私有片段或数据

## 考虑过的替代方案

- **保留两棵树，系统模块顺带写 HM**：可逐个迁移，但 NixOS 与 darwin 共用文件需按平台判断，否则 `homebrew` 等选项不存在时报错；分层与组合仍依赖开关
- **保留 `enable` 开关，用 suite 批量打开**（snowfall-lib 风格）：主机中仍是一组开关，同一职责在两处管理，且容易与实际主机职责脱节
- **按 `key` 包装每个模块以自动去重**：能放宽单一导入路径约束，但每次加入角色都要多写一层包装；真实多路径需求出现时再引入

## 后果

- flake-parts 不为发布的模块设置 `key`，同一模块导入两次不会去重：列表选项重复，声明选项的模块直接报错。因此一台主机上每个模块只能有一条导入路径：HM 侧不写角色 imports 链、功能只加入一个角色、主机不单独导入角色内已有功能、不同时导入互相包含的角色
- `calcUniformSchedule` 按 `hosts/` 下的目录数排定备份时段，新增 `hosts/` 目录会改变所有主机的备份时段；无硬件配置的求值测试机不建目录，角色直接声明在主机表
- 角色名与功能名共用 `flake.modules.<类>` 命名空间，功能不能命名为 `core`、`tui`、`gui`、`desktop`、`workstation`、`homelab`
- 同名挂接会为每个 HM 功能生成 `nixos.<名>` 与 `darwin.<名>`，只适用于 darwin 的功能在 NixOS 上导入会因缺少选项报错
- 模块合并时层级越深越靠前，角色链会改变列表选项的顺序，影响 Brewfile 与 `system-path` 的包排列；`system-path` 开启了 `ignoreCollisions`，同优先级时先出现的包胜出，迁移时需确认首次出现顺序无冲突
