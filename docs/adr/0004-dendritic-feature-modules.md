# 按功能内聚的 Dendritic 模块结构

日期: 2026-10-23

同一功能的配置按层分散在 `modules/darwin/` 与 `home/` 两棵树，改一个功能要改两处，开关还要在主机配置里手动镜像。现在用 flake-parts 加 import-tree：一个功能一个目录，以 `flake.modules.<类>.<名>` 发布，类为 `darwin`、`nixos`、`homeManager`；`modules/flake/features.nix` 把 `homeManager.<名>` 自动挂到同名系统模块，功能文件不写接线代码。功能自己声明加入哪个角色，主机只导入角色。仓库没有独立运行的 Home Manager，`homeConfigurations` 从系统配置求值结果导出，HM 只能由系统模块经 `home-manager.sharedModules` 注入

## 规则

- **一条导入路径**：一台主机上每个模块 MUST 只有一条导入路径。flake-parts 不为模块设 key，导入两次不去重，列表选项重复、声明选项的模块直接报错
- **角色链**：darwin 为 `core ⊂ tui ⊂ gui ⊂ desktop ⊂ workstation`，NixOS 为 `core ⊂ tui ⊂ gui`；每台主机 MUST 恰好导入一个主角色，MAY 并列导入附加角色
- **包含关系只写在系统侧**：角色间的 imports MUST 只出现在 `darwin.<角色>` 与 `nixos.<角色>`，HM 侧 MUST NOT 写角色包含链
- **HM 锚点**：`homeManager.<角色>` MAY 声明本层的 HM 配置与 imports，纯 HM 功能 MAY 一行挂进 `homeManager.<角色>.imports` 同时覆盖两端；已有同名系统模块的功能 MUST NOT 再挂，会重复导入
- **差异落点**：某个角色的所有主机需要 MUST 加入该角色；跨角色的 2 台以上主机需要 SHOULD 建附加角色；只有一台主机需要 MUST 由主机直接导入；都需要但参数不同，功能声明选项、主机设值，HM 部分经 `osConfig` 读取
- **可选功能**：没有主机启用的功能 MUST NOT 加入任何角色、MUST NOT 保留 `enable` 开关，要用的主机在 `imports` 里声明
- **互斥实现** MUST 用 enum 选项（如 `shelken.wm.manager`），MUST NOT 拆成多个可选功能，否则各主机都要显式导入且拦不住同时导入
- **接口放 core**：会被其他功能写入的选项 MUST 声明在 `darwin.core` 与 `nixos.core`，单平台选项声明在对应平台 core，否则未导入实现的主机求值失败
- **密钥是主机属性**：sops 模块放 core，`shelken.secrets.enable` MUST 由主机设置；需要密钥的功能 MUST 声明 `sops.secrets.*` 并断言，MUST NOT 替主机打开
- **HM 配置跟随应用本体**：应用由系统侧安装时，其 HM 配置 MUST 并入同一功能，MUST NOT 整体挂到角色上
- **软链路径字面量**：`mylib.mkConfigLink`、`mkConfigFile` MUST 接收 `./x` 路径字面量，文件挪动后求值即报错
- 路径含 `/_` 的文件 MUST NOT 被自动导入，用于私有片段与数据

## 考虑过的替代方案

- 保留两棵树、系统模块顺带写 HM：共用文件要按平台判断，`homebrew` 等选项不存在时报错
- 保留 `enable` 开关用 suite 批量打开：同一职责在 suite 与主机两处管理
- 按 `key` 包装模块自动去重：每次加入角色多一层包装；真实多路径需求出现再引入

## 后果

- `calcUniformSchedule` 按 `hosts/` 目录数排定备份时段，新增目录会平移所有主机的备份时段；无硬件配置的求值测试机 MUST NOT 建目录，角色直接声明在主机表
- 功能名 MUST NOT 与 `modules/profiles/` 下任何角色同名，两者共用 `flake.modules.<类>` 命名空间
- 同名挂接为每个 HM 功能生成 `nixos.<名>` 与 `darwin.<名>`，只适用于 darwin 的功能在 NixOS 上导入会因缺选项报错
- 模块合并层级越深越靠前，角色链改变列表选项顺序；`system-path` 开了 `ignoreCollisions`，同优先级排前者胜出，迁移时 MUST 确认同路径文件无冲突
