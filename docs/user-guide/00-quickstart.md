# 快速上手

## 日常命令

| 命令                        | 作用                             |
| --------------------------- | -------------------------------- |
| `just bd`                   | 构建当前机器配置（验证，不切换） |
| `just sw`                   | 构建并切换当前机器配置           |
| `just hm-build` / `just hm` | 仅构建/切换 home-manager         |
| `just`                      | 查看全部快捷命令                 |

## 修改配置

1. 改动 `modules/features/<分类>/<功能>`（一个软件的系统侧与用户态配置都在这里）或 `hosts/<机器>/`（机器专属）；功能加入哪个角色见 [ADR 0002](../adr/0002-dendritic-feature-modules.md)
2. `just bd` 验证构建
3. `just sw` 切换生效（新文件先 `git add`，否则 flake 检测不到）

## 进一步阅读

- [声明式定时任务](01-tasks.md)
