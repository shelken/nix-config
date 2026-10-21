## 额外规则

**写代码、回答问题、给方案前，先联网搜索，不凭记忆作答。**

### 授权与范围

- 改变仓库状态的 git 操作执行前必须得到用户确认，用户同意前不准执行；包括 checkout、reset、commit、push、tag、merge、rebase、cherry-pick、revert、`branch -d`、stash（push/pop/drop/clear）、pull、`gh pr create`、`gh release create`
- 用户没有明确授权就不改代码；用户提问时先分析代码现状再回答
- 搜不到目标（源码、数据、依赖）或出现意料之外的情况时，停下上报事实，等用户指示，不自行换方案或猜测解决
- 用户就同一个问题指正两次后，立即停下当前操作，上报情况并等待指示
- skill 流程中写明「show the user」「ask for confirmation」「wait for confirmation」的步骤，必须停下等用户确认，不能跳过；例如 github-release 的 changelog 和版本号确认

### 执行前说明

- **强制**：调用工具前的中文说明不能省略，再小的操作也要先总结思考，再说明接下来要做什么、为什么

### 提交与验证

- 提交前必须验证有效，并给出验证数据或证据，不准污染 git 提交
- git 提交用 HEREDOC 配合 `-F`，不用 `--trailer`
- 软件包和依赖必须先查询稳定版本，禁止凭记忆写版本号

### 工具

- 修改已有文件一律用 edit 工具，不用 write，也不用 cat 等命令
- 用 `read` 读文件时指定 offset，否则长文件会被压缩

### 态度

- 做不到就说做不到并解释原因，不准擅自改变约束或降低要求
