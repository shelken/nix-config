# Otty Configuration

**已归档（仅作配置参考，日常未启用）**

## 配置说明

**生效方式**：`_otty-hm.nix` 通过 `pkgs.replaceVars` 生成配置（`default.nix` 只把该功能挂到 darwin / nixos 的 gui 角色），字体族来自 `vars/default.nix`

修改 `config.toml` 或字体变量后执行 `just hm`

## 注意事项

- `otty config reload` 与 `⌘⌃,`（reload_config）快捷键不可靠，配置更新后建议通过 Settings → Advanced → Config File → Reload Config 或命令面板 `Reload Config` 重载

## 与 kitty 的对应

| kitty                    | otty                                                |
| ------------------------ | --------------------------------------------------- |
| `fontFamilies.monospace` | 同                                                  |
| background_opacity 0.88  | background-opacity 0.88（config.toml 中已注释停用） |
| macos_option_as_alt      | macos-option-as-alt                                 |
| tab sidebar / bottom bar | window-layout = sidebar-left                        |
| Catppuccin Macchiato     | Catppuccin Mocha（内置无 Macchiato）                |
| cmd+[ / ] 切 tab         | 同                                                  |
| cmd+ctrl+, reload        | cmd+ctrl+comma=reload_config                        |
