# Otty Configuration

**archived不使用仅存档**

## 配置说明

**生效方式**：`default.nix` 通过 `pkgs.replaceVars` 生成配置，字体族来自 `vars/default.nix`

修改 `config.toml` 或字体变量后执行 `just hm`

## 踩坑

- `otty config reload` 有时不可靠，构建后用 `⌘⌃,`（reload_config）或命令面板 `Reload Config`

## 与 kitty 的对应

| kitty                    | otty                                 |
| ------------------------ | ------------------------------------ |
| `fontFamilies.monospace` | 同                                   |
| background_opacity 0.88  | background-opacity 0.88              |
| macos_option_as_alt      | macos-option-as-alt                  |
| tab sidebar / bottom bar | window-layout = sidebar-left         |
| Catppuccin Macchiato     | Catppuccin Mocha（内置无 Macchiato） |
| cmd+[ / ] 切 tab         | 同                                   |
| cmd+ctrl+, reload        | cmd+ctrl+comma=reload_config         |
