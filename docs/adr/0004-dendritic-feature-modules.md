# 按功能内聚的 Dendritic 模块结构

日期 2026-10-23

旧结构把同一功能的配置拆在 `modules/darwin/` 与 `home/` 两棵树，改动要同步两处，开关也要在主机配置里镜像。现在仓库用 flake-parts 加 import-tree 组织功能，每个功能在一处以 `flake.modules.<类>.<名>` 发布 `darwin`、`nixos`、`homeManager` 三类模块。`modules/flake/features.nix` 自动将 `homeManager.<名>` 挂到同名系统模块。功能自己声明加入的角色，主机只导入角色。仓库没有独立运行的 Home Manager，`homeConfigurations` 从系统配置求值结果导出

## 规则

- 一台主机上每个模块必须只有一条导入路径。flake-parts 不给模块设 `key`，导入两次不会去重，列表选项会重复，声明选项的模块直接报错
- 每台主机必须恰好导入一个主角色，可以并列导入附加角色，角色包含链定义在 `modules/profiles/`
- 角色之间的包含关系必须只写在 `darwin.<角色>` 与 `nixos.<角色>`，HM 侧不得写角色包含链
- `homeManager.<角色>` 可以声明本层的 HM 配置与 `imports`，纯 HM 功能可以挂进 `homeManager.<角色>.imports` 同时覆盖两端。已有同名系统模块的功能不得再挂进 `homeManager.<角色>.imports`
- 某角色全部主机都需要的功能必须加入该角色，跨角色 2 台以上主机需要的功能应当建附加角色，仅 1 台主机需要的功能必须由主机直接导入。全部需要但参数不同时，功能声明选项由主机设值，HM 经 `osConfig` 读取
- 没有主机启用的功能必须做成可选功能，不得加入任何角色，不得保留 `enable` 开关
- 互斥实现必须用 enum 选项表达，不得拆成多个可选功能
- 会被其他功能写入的选项接口必须声明在 `darwin.core` 与 `nixos.core`，单平台选项声明在对应平台 `core`
- 用户态密钥是主机属性，`shelken.secrets.enable` 必须由主机设置。依赖密钥的功能必须声明并断言它，不得替主机开启
- 应用由系统侧安装时，其 HM 配置必须并入同一功能，不得按角色整体挂接
- 功能名不得与 `modules/profiles/` 下任何角色同名
- 路径含 `/_` 的文件不得被自动导入，私有片段规则见 `docs/adr/0012-feature-domains-and-file-form.md`

## 考虑过的替代方案

- 保留两棵树并在系统模块里顺带写 HM。跨平台文件要到处判断平台，角色组合仍依赖开关
- 保留 `enable` 开关用 suite 批量开启。同一职责在 suite 和主机两处维护，容易失配
- 给每个发布模块包装 `key` 自动去重。每次挂接都要包一层，等出现真实多路径需求再引入
