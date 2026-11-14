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
5. 在需要它的功能的 Home Manager 模块里声明 `shelken.dev.ai.skills = [ "${inputs.<input>}/<仓库内目录>" ];`（列表追加一项）：所有导入 `ai` 的机器都需要的写在 `modules/features/ai/skill.nix` 的 `ai` 声明里，只在部分机器需要的写在所属功能目录（ADR 0008、0009）；要覆盖 frontmatter 时写 `{ source = …; frontmatter.<字段> = …; }`
6. 只加 input 与声明时，验证到 `nix flake lock` 与 `nix eval --json .#skillUpstreams.<本机>`（输出里有新目录）即可，不跑 `just hm-build`、`just hm`；见 `.agents/skills/verify-nix-config/features/README.md` 的「When no drive is required」
7. 涉及 `skill.nix` 的部署逻辑、部署路径或依赖 CLI 时，仍按 `verify-nix-config` 驱动对应 feature 后提交

## 补全依赖 CLI

若该 skill 依赖特定 CLI 工具，且 `modules/features/ai/cli.nix` 尚未定义：

1. 检索 nixpkgs 是否已有该 CLI：`nix-search-tv print | grep <cmd-cli-name>`；若有优先使用 nixpkgs 来源，在 `home.packages` 直接使用
2. 若 nixpkgs 里没有，在 `modules/features/ai/cli.nix` 的 `programs.mise.globalConfig.tools` 用 mise 后端（`npm:`、`pypi:`、`github:`）声明并钉死版本，上一行写 renovate 注释；不用 `bunx`、`npx`、`uvx` 现取。命令名必须与 skill 中调用的一致（例如 skill 调用 `bili`，而包的可执行文件叫别的名字，则用 `writeShellScriptBin` 做别名）
3. 执行 `just hm` 和 `mise install`，验证新安装的 CLI 能正常调用

## 注意事项

- 日常的 rev 前进由 Renovate 按 input 开 digest PR；手动改只动目标 input 的 rev，避免顺带刷新其他源
- 优先使用 nixpkgs 预编译二进制产物，避免本地编译开销
- 若依赖包体积过大（如 LibreOffice 等），先向用户说明并在必要时按需安装
