---
name: add-external-skill
description: 引入外部 skill 时使用，指导从 GitHub 仓库拉取、配置 nvfetcher、引用至 skill.nix 并补全 CLI
---

## 使用时机

- 需要从外部仓库引入新的 skill

## 流程

1. 获取用户提供的 skill 链接（通常为 GitHub 仓库）
2. 阅读 `nvfetcher.toml` 与 `modules/features/ai/skill.nix` 现有配置
3. 在 `nvfetcher.toml` 中按字母序添加该 skill，执行精准拉取：
   ```bash
   nvfetcher -c nvfetcher.toml -f '^{skill_name}$'
   ```
4. 在 `modules/features/ai/skill.nix` 中按字母序声明引用
5. 执行 `just hm` 应用 Home Manager 配置
6. 验证安装结果并提交

## 补全依赖 CLI

若该 skill 依赖特定 CLI 工具，且 `modules/features/ai/cli.nix` 尚未定义：

1. 检索 nixpkgs 是否已有该 CLI：`nix-search-tv print | grep <cmd-cli-name>`；若有则优先使用 nixpkgs 来源，加入 `home.packages`
2. 若无官方包，根据 skill 文档指引使用 `bunx`、`npx` 或 `uvx` 封装，确保命令别名与 skill 中的调用名完全一致
3. 执行 `just hm` 并验证 CLI 能否正常调用

## 注意事项

- `nvfetcher` 更新时限定单个 skill，避免无谓刷新其他仓库
- 优先使用 nixpkgs 预编译二进制产物，避免本地编译开销
- 若依赖包体积过大（如 LibreOffice 等），先向用户说明并在必要时按需安装
