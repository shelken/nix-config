# 问题跟踪器：GitHub

本仓库的问题、产品需求和路线地图使用 GitHub Issues 管理。所有操作使用 `gh` 命令。

## 基本操作

- 创建问题：`gh issue create --title "..." --body "..."`
- 读取问题：`gh issue view <编号> --comments`
- 列出问题：`gh issue list --state open --json number,title,body,labels,comments`
- 评论问题：`gh issue comment <编号> --body "..."`
- 添加或移除标签：`gh issue edit <编号> --add-label "..."` / `--remove-label "..."`
- 关闭问题：`gh issue close <编号> --comment "..."`

多行正文使用 heredoc。仓库从当前目录的 Git 远端推断。

## 拉取请求作为需求入口

否。外部拉取请求不进入需求分诊队列。

## 技能操作约定

- “发布到问题跟踪器”：创建 GitHub Issue。
- “读取相关任务”：运行 `gh issue view <编号> --comments`。
- GitHub 的问题和拉取请求共用编号；编号类型不明确时，先尝试 `gh pr view`，再尝试 `gh issue view`。

## Wayfinding operations（路线规划操作）

Wayfinder 使用一个地图问题和多个子问题管理路线。

- **地图**：标签为 `wayfinder:map` 的问题，正文保存终点、说明、已完成决策索引、尚未明确内容和范围外事项。
- **子任务**：使用 GitHub 子问题关系挂到地图下，并添加以下标签之一：
  - `wayfinder:research`
  - `wayfinder:prototype`
  - `wayfinder:grilling`
  - `wayfinder:task`
- **子问题不可用时**：在地图正文使用任务列表，并在子任务正文顶部写 `Part of #<地图编号>`。
- **阻塞关系**：优先使用 GitHub 原生问题依赖；不可用时在正文顶部写 `Blocked by: #<编号>`。
- **可执行前沿**：地图下所有未关闭、无未完成阻塞、无人领取的子任务。
- **领取**：开始工作前先运行 `gh issue edit <编号> --add-assignee @me`。
- **解决**：先添加结论评论，再关闭子任务，最后在地图的“已完成决策”中追加一条名称、链接和结论摘要。
- 面向用户的文字始终使用任务名称；编号只放在名称链接中，不单独代替任务名称。
