# 快速上手

## 日常命令

| 命令                           | 作用                        |
| ------------------------------ | --------------------------- |
| `just bd`                      | 构建当前机器配置，不切换    |
| `just b <主机>`                | 构建指定主机的配置，不切换  |
| `just sw`                      | 构建并切换当前机器配置      |
| `just hm-build` / `just hm`    | 仅构建 / 切换 Home Manager  |
| `just plan [主机] [种类]`      | 构建前看要编译、下载什么    |
| `just up` / `just upp <input>` | 更新全部 / 指定 flake input |
| `just`                         | 查看全部快捷命令            |

当前机器由仓库根目录的 `.host-profile`（`PROFILE=<主机>`）决定，首次设置见根目录 README「初始化」

## 修改配置

1. 修改 `modules/features/<分类>/<功能>`（软件的系统侧与用户态配置）或 `hosts/<主机>/`（机器专属），具体写法见 [功能与角色](02-features.md)
2. 运行 `just bd` 验证构建
3. 运行 `just sw` 切换生效；新增文件需先执行 `git add`，否则 flake 无法检测

## 构建前看要编译什么

`just plan` 只求值、不构建，列出这次会真编译的包和要下载的量。种类为 `system`（默认）、`home`、`deploy`

```bash
just plan                  # 当前机器的系统
just plan mio home         # mio 的 Home Manager
just plan vps-cc deploy    # vps-cc 的 deploy-rs 部署 profile
```

```text
将构建 60 个派生：编译 1，源码下载 0，生成 59
  编译  rust     deploy-rs-1.0.0
将下载 208 个路径（54.1 MiB download, 2.2 GiB unpacked）
  其中编译工具链（说明有东西要现编）：
    rustc-1.99.0
```

| 类别     | 是什么                                         | 代价                   |
| -------- | ---------------------------------------------- | ---------------------- |
| 编译     | cache 里没有的软件包，本机现编，后面是所用语言 | 慢，还要下载工具链     |
| 生成     | 配置文件、包装脚本、系统组装层                 | 几秒，每次改配置都会有 |
| 源码下载 | 编译前要取的源码包                             | 只占下载               |

出现不想要的编译时，查是谁引入的

```bash
nix why-depends --derivation .#darwinConfigurations.<主机>.system <「编译」那行的 .drv 路径>
```

常见原因是 flake 输入的软件包 `follows` 到本仓库的 nixpkgs，或 overlay 改写了某个包。能用 nixpkgs 自带的同名包时优先用它，deploy-rs 的激活器就是这样处理的（`lib/deployRsLib.nix`）

## 进一步阅读

- [功能与角色](02-features.md)
- [声明式定时任务](01-tasks.md)
- [备份](04-backup.md)
