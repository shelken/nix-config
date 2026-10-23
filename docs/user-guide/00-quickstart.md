# 快速上手

## 日常命令

| 命令                           | 作用                        |
| ------------------------------ | --------------------------- |
| `just bd`                      | 构建当前机器配置，不切换    |
| `just b <主机>`                | 构建指定主机的配置，不切换  |
| `just sw`                      | 构建并切换当前机器配置      |
| `just hm-build` / `just hm`    | 仅构建 / 切换 Home Manager  |
| `just up` / `just upp <input>` | 更新全部 / 指定 flake input |
| `just`                         | 查看全部快捷命令            |

当前机器由仓库根目录的 `.host-profile`（`PROFILE=<主机>`）决定，首次设置见根目录 README「初始化」

## 修改配置

1. 改动 `modules/features/<分类>/<功能>`（一个软件的系统侧与用户态配置都在这里）或 `hosts/<机器>/`（机器专属），具体写法见 [功能与角色](02-features.md)
2. `just bd` 验证构建
3. `just sw` 切换生效（新文件先 `git add`，否则 flake 检测不到）

## 进一步阅读

- [功能与角色](02-features.md)
- [声明式定时任务](01-tasks.md)
