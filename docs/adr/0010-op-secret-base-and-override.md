# 0010 凭据注入分为 1Password 基座与 specific.zsh 覆盖层

日期: 2026-10-25
状态: Accepted

## 背景

`~/.specific.zsh` 此前以明文存放全部 API key（18 个，权限 600），`sec-run` 启动目标命令时 source 它。本地明文意味着机器失窃或目录误同步即泄密；临时切换账号（key 没余额换备用号）靠注释行，无法区分"长期值"与"临时值"。

已确认的事实基础：`op run --env-file` 支持 `export` 前缀、`#` 注释、多个 `--env-file` 后者覆盖前者、明文值原样透传（实测 op 2.41.1）。

## 决策

1. **基座进仓库**：`modules/features/secrets/secrets.nix` 的 `opSecretMap` 声明变量名 → `op://Personal/<条目名>/credential` 引用，构建期生成只含引用的 env 文件进 nix store。真实值只在 1Password。
2. **specific.zsh 保留为覆盖层**：文件继续存在，语法不变（`export KEY=...`、`#` 注释），但语义变为"临时覆盖基座"。同名变量覆盖层赢；注释一行即回落基座值。值允许明文，推荐 `op://` 引用（如指向备用账号条目）。
3. **sec-run 改为 `exec op run --env-file=<基座> [--env-file=<specific.zsh>] -- "$@"`**：op CLI 不存在（如 Linux 无头机）时跳过 op 层，退回 source specific.zsh 的旧行为。sops 的 GITHUB_TOKEN 注入保持不变，先于 op 层执行。
4. **一次性迁移**：`utils/script/migrate_specific_to_op.sh` 把 specific.zsh 现有明文逐键建为 Personal vault 的 API Credential 条目（条目名 = 变量名，幂等可续传），完成后把文件重置为空覆盖层。

## 后果

- 本地磁盘不再持有任何 key 明文（sops 管的除外，见下）
- 条目名 = 变量名带来约束：变量改名需同步改 vault 条目名与基座映射；接受，换取映射零歧义
- GITHUB_TOKEN 仍走 sops：它与 gh-hosts.yml 模板、任务系统耦合，迁 op 需另动 sops 模板，不在本次范围
- op 锁定时 `sec-run` 直接报错退出（可见失败优于静默缺凭据）
- 认证提示：Touch ID 集成下按终端会话缓存（10 分钟不活动失效，最长 12 小时），不跳浏览器
- 条目名与变量名的对应关系公开进仓库（`opSecretMap`），条目名本身不含敏感信息

## 考虑过的替代方案

- **`~/.config/secrets.local.env` 新文件做覆盖层**：多一个文件多一份心智负担，specific.zsh 语法与用户既有肌肉记忆（注释切换）完全兼容，无收益
- **service account token（`OP_SERVICE_ACCOUNT_TOKEN`）免弹窗**：长期明文 token 落盘，违背本次"本地零明文"目标，只适合无头机器
- **全部迁 sops**：sops 无按需解密与 GUI 管理，失去 1Password 的账号切换便利；且 GITHUB_TOKEN 之外再引入第二套 secret 来源没有意义
