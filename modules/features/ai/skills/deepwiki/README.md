# 上游来源

取自 [kasuboski/pi-extensions](https://github.com/kasuboski/pi-extensions) 的 `skills/deepwiki`，对应上游提交 [`e9e0213`](https://github.com/kasuboski/pi-extensions/commit/e9e02134361ea6657a080a8d3b035b68b9dc8525)（2026-04-17）

## 与上游的差异

只有 `SKILL.md` 有改动
- 命令由 `bunx @seflless/deepwiki <子命令>` 改为 `deepwiki <子命令>`，对应 `../../cli.nix` 中封装的 `deepwiki` 命令
- 开头一句由「Assumes Node.js is installed」改为「The `deepwiki` CLI is pre-installed via nix」
