# Otty Configuration

**archived不使用仅存档**

## 配置说明

**生效方式**：`default.nix` 用 `mkOutOfStoreSymlink` 把仓库内 `config.toml` 软链到 `~/.config/otty/config.toml`（同 aerospace/herdr）。

改字体/快捷键/主题直接改仓库里的 `config.toml` 即可，无需 rebuild；新增/删除此模块本身才需要 `just hm`。

## 踩坑

- Otty Settings / `otty config set` 会写穿软链并重写本文件 -> 尽量只改仓库文件；少用 UI/`config set` 改会落盘的项
- 多层软链下文件 watch / `otty config reload` 有时不可靠 -> 改完用 `⌘⌃,`（reload_config）或命令面板 `Reload Config`

## 与 kitty 的对应

| kitty                    | otty                                 |
| ------------------------ | ------------------------------------ |
| Iosevka Nerd Font Mono   | 同                                   |
| background_opacity 0.88  | background-opacity 0.88              |
| macos_option_as_alt      | macos-option-as-alt                  |
| tab sidebar / bottom bar | window-layout = sidebar-left         |
| Catppuccin Macchiato     | Catppuccin Mocha（内置无 Macchiato） |
| cmd+[ / ] 切 tab         | 同                                   |
| cmd+ctrl+, reload        | cmd+ctrl+comma=reload_config         |
