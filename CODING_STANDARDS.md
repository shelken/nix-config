# 编码规范

日常编码、提交与验证的项目约定

## 编码与提交

- 注释与文档使用中文
- commit 前先 `git add`，然后运行一次 pre-commit
- 优先使用 Conventional Commits 格式提交，标题英文，正文中文

## 验证

- 修改配置后，只有本机情况（检查 `.host-profile` 对应的 PROFILE）才使用 `just bd`（nix-darwin 范围验证）/ `just hm-build`（home-manager 范围验证）等命令进行验证；其他机器的情况仅使用轻量化的命令进行校验

## 工具

- 一般使用 `nh search` 搜索 nixpkgs 中的包

## 放置约定

- 项目级 skill 必须放在仓库根 `.agents/skills/` 下，不要放到 `home/` 等用户环境配置目录
