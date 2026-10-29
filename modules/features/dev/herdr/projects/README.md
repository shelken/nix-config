# herdr-plus Projects

每个 `.toml` = 一个可 fuzzy 选择的 **workspace 启动模板**。  
本目录经 home-manager 软链到：

`~/.config/herdr/plugins/config/cloudmanic.herdr-plus/projects`

修改后立刻生效，无需重新安装插件；打开快捷键为 `prefix+p`（默认 prefix 为 `Alt+x`，或执行 action `cloudmanic.herdr-plus.projects`）

---

## 顶层字段

| 字段          | 必填 | 说明                                                                     |
| ------------- | ---- | ------------------------------------------------------------------------ |
| `name`        | 是   | 列表里显示的名字                                                         |
| `description` | 否   | 副标题/说明                                                              |
| `group`       | 否   | 分组标签（如 `home` / `active`），便于筛选                               |
| `working_dir` | 否\* | 默认工作目录；支持 `~`。有 `[[tabs]]` 时建议写上                         |
| `command`     | 否\* | **单 tab 快捷写法**：整个 workspace 只跑这一条命令。与 `[[tabs]]` 二选一 |
| `env`         | 否   | 注入环境变量表，例如 `FOO = "bar"`                                       |
| `[[tabs]]`    | 否\* | 多 tab 布局。与顶层 `command` 二选一                                     |

\* 必须在顶层 `command` 与 `[[tabs]]` 中声明至少一项

---

## `[[tabs]]`

| 字段             | 说明                                                            |
| ---------------- | --------------------------------------------------------------- |
| `name`           | tab 名                                                          |
| `working_dir`    | 覆盖顶层 cwd（可选）                                            |
| `command`        | 该 tab **单 pane** 启动命令。与 `[[tabs.panes]]` **不能同时写** |
| `[[tabs.panes]]` | 多 pane 布局（每 tab 最多 4 个）                                |

---

## `[[tabs.panes]]`（pane 布局）

| 字段      | 说明                                                    |
| --------- | ------------------------------------------------------- |
| `command` | 该 pane 启动命令；省略 = 空终端                         |
| `label`   | 可选标签                                                |
| `split`   | 相对**前一个** pane 的分割方向：`down`（默认）/ `right` |

规则：

1. **第一个 pane 是根**，其 `split` 无效
2. 后续 pane 依次相对前一个 split
3. 每 tab 最多 **4** 个 pane
4. 无「宽高比例」配置，只有顺序 split

示例：左 pi、右 shell

```toml
[[tabs]]
name = "main"

[[tabs.panes]]
label = "pi"
command = "pi"

[[tabs.panes]]
label = "shell"
split = "right"
```

---

## Worktree 模式

Projects 列表中支持通过 **Ctrl+g** 以 git worktree 模式打开（要求目标仓库为 Git 仓库）

字段定义保持一致，具体行为以 herdr-plus 官方文档为准

---

## 本仓库约定

- 文件名：`kebab-case.toml`，与 `name` 一致
- `group`：`home`（nix-config / MyRepo）或 `active`（`~/Code/active`）
- 默认布局：左 `pi` + 右空终端，再加一个空 `term` tab

最小模板：

```toml
name = "example"
description = "…"
group = "active"
working_dir = "~/Code/active/example"

[[tabs]]
name = "main"

[[tabs.panes]]
label = "pi"
command = "pi"

[[tabs.panes]]
label = "shell"
split = "right"

[[tabs]]
name = "term"
```
