---
name: add-external-skill
description: 获取外部 skill 时使用
---

## 使用时机

- 需要从外部仓库引入新的 skill

## 流程

1. 获取用户提供的 skill 链接（通常为 GitHub 仓库）
2. 确认上游默认分支与要锁定的 commit：
   ```bash
   gh api repos/<owner>/<repo> --jq .default_branch
   gh api repos/<owner>/<repo>/git/ref/tags/<tag> --jq '.object.type, .object.sha'
   ```
   分支型源用默认分支上的 commit；tag 型源取 tag 指向的 commit，并用
   `gh api repos/<owner>/<repo>/compare/<sha>...<默认分支>` 确认它在该分支历史上
3. 在 `flake.nix` 的静态资源分区按字母序加 input，`flake = false`：
   ```nix
   <name> = {
     url = "git+https://github.com/<owner>/<repo>?ref=<默认分支>&rev=<sha>&shallow=1";
     flake = false;
   };
   ```
4. 执行 `nix flake lock` 拉取该源
5. 在 `modules/features/ai/_skill-sources.nix` 里按字母序声明分组：`input` 写 input 名，`base` 写仓库内路径前缀，`skills` 写启用的 skill 相对路径
6. 执行 `just hm` 应用 Home Manager 配置
7. 验证安装结果并提交

## 补全依赖 CLI

若该 skill 依赖特定 CLI 工具，且 `modules/features/ai/cli.nix` 尚未定义：

1. 检索 nixpkgs 是否已有该 CLI：`nix-search-tv print | grep <cmd-cli-name>`；若有优先使用 nixpkgs 来源，在 `home.packages` 直接使用
2. 若 nixpkgs 里没有，则根据 skill 文档指引，使用 `bunx`、`npx` 或 `uvx` 直接封装（参考 `modules/features/ai/cli.nix` 现有例子），且确保在 shell 中的名字与 skill 中定义的一致（例如包原名为 `bilibili-cli`，skill 示例中调用 `bili`，则封装后的命令即为 `bili`）
3. 执行 `just hm` 验证新安装的 CLI 是否能正常调用

## 注意事项

- 日常的 rev 前进由 Renovate 按 input 开 digest PR；手动改只动目标 input 的 rev，避免顺带刷新其他源
- 优先使用 nixpkgs 预编译二进制产物，避免本地编译开销
- 若依赖包体积过大（如 LibreOffice 等），先向用户说明并在必要时按需安装
