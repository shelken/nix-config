# 编码规范

日常编码、提交与验证的项目约定

## 编码与提交

- 注释与文档使用中文
- commit 前先 `git add`，然后运行一次 `prek run`
- 优先使用 Conventional Commits 格式提交，标题英文，正文中文
- 项目级 skill 放仓库根 `.agents/skills/`，全局与按功能 skill 的放置规则见 `modules/features/ai/skills/README.md`

## 验证

- 修改配置后，仅本机（`.host-profile` 对应的 PROFILE）使用 `just bd`（nix-darwin 范围）或 `just hm-build`（home-manager 范围）验证，其他机器只做轻量求值校验
- 求值期不得依赖构建（IFD），也不得读 YAML，排查入口为 `just check-ifd`，决策见 `docs/adr/0010-no-ifd-at-eval-time.md`

## 工具

- 一般使用 `nh search` 搜索 nixpkgs 中的包
