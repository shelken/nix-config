# Orca 键位管理

`keybindings.json` 软链到 `~/.orca/keybindings.json`（Orca 官方唯一用户键位文件，源自码 `getUserKeybindingsPath`）。

- 仓库内编辑立即生效：Orca 重启，或 Settings → Shortcuts → Reload from Disk
- Orca UI 内改键会写穿回本文件
- 当前仅解绑 `terminal.expandPane`（Cmd+Shift+Enter），避免吞掉 omp 的 `app.message.followUp`
