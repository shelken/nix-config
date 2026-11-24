# nix-config

基于 Nix Flakes 的多平台配置仓库，管理 macOS (nix-darwin) 和 Linux (NixOS) 的系统与 Home Manager 配置

## 布局

- `modules/features/<分类>/<功能>`：按功能内聚的跨平台配置，结构规则见 `docs/adr/0004-dendritic-feature-modules.md`，领域与文件形式见 `docs/adr/0012-feature-domains-and-file-form.md`
- `modules/profiles/` 与 `modules/flake/`：主机角色、附加角色定义（见 `docs/adr/0004-dendritic-feature-modules.md`）与 flake-parts 胶水模块
- `hosts/`：主机与主路由配置入口（`hosts/router-mine/` 由 nuci 管理，见 `just/router.just`），`.host-profile` 记录本机 flake 名
- `vars/`、`lib/`、`secrets/`：全局变量、自定义函数与 sops-nix 秘密管理
- `GLOSSARY.md`、`CODING_STANDARDS.md`、`docs/adr/`：共享领域词表、编码提交与验证规范、架构决策记录

## 约束

- 未经用户允许，不使用 `just sw`（nix-darwin 范围变更）与 `just hm`（home-manager 范围变更）
- 安装包的方式必须与用户确认
- 执行任何 nix 操作（eval/build）前，确保新增或删除的文件已被 git 跟踪
- 新增或调整软件配置前，先读 `docs/agents/software-config.md`
- `docs/adr/` 只放与 nix、本仓库、dotconfig 有关的决策，规范句按 RFC 2119 使用中文限定词（必须、不得、应当、可以）；具体软件或脚本的设计放其代码目录的 `README.md`
- 创建、修改或测试机器特定定时任务时使用 `.agents/skills/create-task/`
- 修改或新增本地技能（`modules/features/ai/skills/` 或功能目录下经 `shelken.dev.ai.skills` 登记的）前，先读 `modules/features/ai/skills/README.md`
- 公开项目，不得在 Issue、PR、提交或代码中包含任何个人敏感信息或设备运行环境数据
