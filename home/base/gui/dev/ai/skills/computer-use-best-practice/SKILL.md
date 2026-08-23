---
name: computer-use-best-practice
description: 当需要读取或控制 macOS App 界面时使用
---

## Workflow

1. 项目已有专用控制方式时优先使用，否则使用 `cua-driver`。未安装时停止并告知用户。
2. 首次调用工具前运行 `cua-driver describe <name>`；`list-tools` 只用于发现工具。
3. 选择唯一窗口。当前 App 用 `list_apps` 配合 `list_windows`；指定 App 用 `get_accessibility_tree`，同时检查 `app_name` 和 `title`。存在多个候选时先消除歧义。
4. 调用 `get_window_state` 读取界面。优先传入 `query` 并关闭截图；用 `tree_markdown` 理解结构，用 `elements` 获取可操作 token。
5. 优先使用最近一次读取返回的 `element_token` 操作。token 失效时重新读取，不复用或硬编码 token。
6. 操作后重新读取窗口，并根据新的状态确认预期结果。命令成功不代表任务完成。

## Rules

- Accessibility 路径不可用时才使用像素坐标。坐标来自窗口截图且相对窗口；先用默认后台投递，需要前台交互时才设为 `foreground`。
- 工具返回权限错误时运行 `cua-driver permissions status`，不要把权限检查加入每次操作。
- 需要临时文件时使用 `mktemp`。构造包含外部文本的 JSON 时使用 `jq -n --arg` 或等价的安全编码方式。
- 每次操作前确认目标窗口仍然匹配原来的 `pid`、`window_id` 和标题，避免对陈旧窗口执行副作用。
