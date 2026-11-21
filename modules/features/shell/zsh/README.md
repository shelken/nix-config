## 说明

- prompt 由 `../starship.nix` 管理（Starship，配色来自 catppuccin/nix）
- 补全由 `fzf-tab` 管理，`tui` 及以上角色同时启用 `../carapace.nix`

## 特定配置

`$HOME/.specific.zsh` 是凭据**覆盖层**：基座值来自仓库 `modules/features/secrets/secrets/default.nix` 的 `opSecretMap`（`op://` 引用，由 1Password 解析），覆盖层只放临时差异；`sec-run` 运行目标命令前用 `op run` 把两者解析进环境，主终端默认不加载；解析不了的引用会被跳过并在 stderr 警告，其余照常注入

- 临时换值/切换备用账号：`sec-env add KEY "op://Agent/<条目>/credential"`
- `op://` 引用只能指向 `Agent` vault：`sec-run` 用只读 service account 解析，它看不到其他 vault，指向别处的引用会被跳过
- 回落到基座值：注释掉或 `sec-env del KEY`
- 明文值允许但不推荐（迁移期兼容）
- 长期换值直接改 1Password 条目，不动任何文件
