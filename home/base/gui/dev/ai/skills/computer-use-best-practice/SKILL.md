---
name: computer-use-best-practice
description: 当 需要阅读mac上任意App界面的内容/控制任意App/点击任意App 时阅读该技能
---

## 常用命令

JSON 参数统一走 stdin: `echo '{...}' | cua-driver call <tool>`

```bash
# 查某工具的参数说明
cua-driver describe <tool>

# 列出所有窗口, 找目标 app 的 window_id 和 pid
cua-driver call list_windows --json

# 聚焦窗口: Electron 应用必须先聚焦, 无障碍树才有渲染内容
echo '{"pid":<pid>,"window_id":<id>}' | cua-driver call bring_to_front

# 读取窗口内容(首选): 无障碍树, 纯文本比截图准且省
echo '{"pid":<pid>,"window_id":<id>,"include_screenshot":false}' | cua-driver call get_window_state

# 无障碍树为空时的兜底: 截图(去掉 include_screenshot 即返回), 解码 screenshot_png_b64 字段

# 按 element_index 交互: 点击/输入/按键
echo '{"element_index":<n>}' | cua-driver call click
echo '{"element_index":<n>,"text":"..."}' | cua-driver call type_text
```

## Rules

- `cua-driver --help` 运行命令查看如何使用, 如果没有安装, 跳过并告知用户
