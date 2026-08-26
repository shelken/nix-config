---
name: computer-use-best-practice
description: 当 需要阅读mac上任意App界面的内容/控制任意App/点击任意App 时阅读该技能
---

## Rules

- 除非项目有更专用的控制方式, 否则使用 `cua-driver`
- `cua-driver --help` 看用法; 工具参数在 `describe <name>`, 用前先读; skill 只写查不到的逻辑
- 不抢焦点: 启动用 `open -g`; 操作默认 `background`; 仅 `delivery_failed` 才 `foreground` (用毕自动恢复)

## 读取

一次 `get_window_state` = 一份服务端快照 (`tree_markdown` + `elements` 同一组 token)。快照供跨调用操作; 再调才废旧 token。bash 调用独立, 不存变量跨调用。

一条主干命令, 输出全元素精简视图 (token/状态/坐标), 按需 jq 过滤:

```bash
# 选窗口
cua-driver call get_accessibility_tree | jq -c '[.windows[]|{app_name,pid,window_id,title}]'
# 读界面 (主干)
cua-driver call get_window_state '{"pid":<pid>,"window_id":<wid>,"include_screenshot":false}' | jq -c '[.elements[]|{i:.element_index,token:.element_token,role:(.role|ltrimstr("AX")),label:.label,selected:.selected,enabled:.enabled,value:.value,frame:.frame}]'
```

变体 (同一条命令改参数): 看结构用 `.tree_markdown` 替代 `.elements`; 按文本收窄加 `"query":"<关键词>"` 服务端过滤; 限规模加 `"max_depth"/"max_elements"`。

多数元素无 `frame`; 仅非 AX 表面需坐标。`tree_markdown` 无 `[index]` 的元素不可用 token。列表容器 (文件/邮件/列表) 的项名常在深层子节点, 按有 label 的 role 过滤, 勿用 `max_depth` 截掉深层项。

## 操作

用最近一次读取的 token 调 click/type_text/press_key (字段: click 用 `action`, type_text 用 `text`, press_key 用 `key`)。读取与操作紧贴, 中间勿再get_window_state否则旧 token 失效。命令成功 ≠ 完成, 用 verify_state 断言 (写法见 describe) 或重读验证真实结果。

```bash
cua-driver call click '{"pid":<pid>,"window_id":<wid>,"element_token":"<token>","action":"press"}'
```

## 坑

- jq 过滤不命中返回 null, null token 报 `invalid_element_token`, 操作前确认非空
- 进程含多 top-level/多个标签: `press_key` 可能被拒, AX 归属判定可能失败/落错 → 用 `foreground` (用毕恢复) 或专用控制工具
- DOM 容器内输入 (webview/网页) `value_readback` 不可靠 (报 confirmed 但文本损坏) → 用专用 CDP 工具或重读验证
- 像素路径 (x,y) 是 synthetic event, 后台/隐藏窗口无效需前台 (仅作非 AX 表面 fallback)
- 权限: `cua-driver permissions status` 排查



