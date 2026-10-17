# Agent Sandbox

通过 Home Manager 提供 `sb-default`，在常驻 Linux VM 中运行 OMP。机器规格使用 [msb 原生 YAML](./sb-default.yaml)，Linux 工具和 OMP 由 [machine.nix](./machine.nix) 与 [wrapper.nix](./wrapper.nix) 提供

## 首次使用

先在宿主应用本仓库的 Home Manager 配置，取得 `sb-default` 命令。构建不会代替激活

为 YAML 引用的命名卷创建独占磁盘。此命令只在该卷尚不存在时执行，`disk` 卷使用 ext4；msb 的默认 `dir` 卷不适合这里的数据库

```bash
msb volume create sb-default-omp --kind disk --size 8G
sec-run sb-default up
```

`sec-run` 必须用于启动 VM，让 msb 在启动时取得 YAML 声明的凭据并建立原生 secret proxy。VM 已运行时，`up` 不会重建其代理；需要刷新凭据时，先停止，再经 `sec-run` 启动

```bash
sb-default down
sec-run sb-default up
```

GitHub CLI 使用原生方式配置 Git HTTPS 凭据助手。此操作写入 guest 自己的 Git 配置

```bash
sb-default exec gh auth setup-git --hostname github.com
```

OMP 插件由应用自身管理，使用 `sb-default exec omp plugin install <source>` 安装，来源参考 [OMP 插件清单](../omp/plugins/package.json)。`up`、`exec` 和 Home Manager 配置发布都不会为 guest 安装、更新或修复插件；宿主插件目录也不会挂入 guest

## 运行 OMP

查看可选模型，再选择当前网络可达的模型。模型配置来自 nix-config，guest 的本机回环地址由 sandbox 适配为宿主地址

```bash
sb-default exec omp --list-models
sb-default exec -t omp --model=mp/qoder-cn/gmodel
```

非交互运行同样经过完整入口，下面的提示要求 OMP 实际执行工具

```bash
sb-default exec omp -p --model=mp/qoder-cn/gmodel '使用 bash 执行 uname -s，回复实际输出'
```

这些示例中的模型必须在当前配置中存在且服务可达。CLI 启动成功与模型请求成功分别验证，某个 provider 超时不会由 sandbox 自动切换模型

## 生命周期

| 命令 | 行为 |
|---|---|
| `sb-default up` | 首次创建并启动 VM，已有 VM 则确保启动；需要凭据时使用 `sec-run sb-default up` |
| `sb-default exec <cmd> ...` | 带 Linux 工具 PATH、原生代理证书和 XDG 目录运行命令 |
| `sb-default exec -t omp` | 分配 PTY 运行 OMP TUI |
| `sb-default shell` | 进入使用相同入口的交互 shell |
| `sb-default status` | 查看 VM 状态 |
| `sb-default down` | 停止 VM，保留磁盘与命名卷 |
| `sb-default rm` | 删除 VM，保留命名卷；不会应用日常配置更新 |

其余命令见 `sb-default --help`

## 配置与状态

| Guest 路径 | 来源与用途 |
|---|---|
| `/workspace` | 宿主 `~/Code`，读写工作目录 |
| `/nix/store` | 宿主 store，只读提供 Linux 工具；guest 不使用 apt 安装系统包 |
| `/root/.omp/agent` | sandbox 从现有 Home Manager 文件声明收集的只读 OMP 配置，不包含宿主数据库或 session |
| `/root/.agents` | 宿主共享的只读 skills 与模型提示词 |
| `/data/xdg/data/omp` | guest 自己的数据库、session 和应用数据 |
| `/data/xdg/state/omp` | guest 自己的 XDG 状态 |
| `/data/xdg/cache/omp` | guest 自己的缓存 |

`/data` 使用这台 VM 独占的 ext4 命名卷。不得让其他 VM 同时挂载该卷写入数据库，也不得改为共享宿主 OMP 状态目录

## 更新配置

配置定义和模型地址适配集中在 [sandbox 模块](./default.nix)。模块消费已有 `home.file` 声明，其他 AI 配置模块不维护 sandbox 文件清单

Home Manager 以 `recursive = true` 发布纯配置目录。宿主挂载根保持为真实目录，配置更新时替换其下的文件链接，供同一 VM 继续读取。日常配置更新不使用 `sb-default rm`

文件可见与进程重读分别处理。下一次启动 OMP 会重新读取配置；已运行的 OMP 是否能热重载，取决于对应设置和 OMP 自身能力。需要重新启动 OMP 时先正常退出，再接回同一 VM，数据库和 session 仍保留

机器资源、挂载规则、网络白名单与 secret 目标的变更属于 VM 规格变更，不等同于日常 OMP 配置更新

## 网络与凭据

网络与 secret 授权以 [sb-default.yaml](./sb-default.yaml) 为准。msb 原生 secret proxy 按声明的目标处理凭据，不共享宿主 SSH 私钥

宿主服务在 guest 中使用 `host.microsandbox.internal`。入口保留 msb 注入的 CA 环境，并让 Git 使用同一证书包；不要通过关闭 TLS 校验排查凭据问题
