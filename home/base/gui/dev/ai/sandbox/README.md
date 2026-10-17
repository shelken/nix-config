# Agent Sandbox

Home Manager 安装 `sb-default` 和 `omp-sb` 两个系统命令。VM 规格使用 [原生 msb YAML](./sb-default.yaml)，命令入口与 Linux 工具集中在 [wrapper.nix](./wrapper.nix)

## 首次准备

宿主需要已有 `msb` 和 `sec-run`。应用本仓库的 Home Manager 配置后，为 VM 创建独占 ext4 磁盘；下面的建卷命令只执行一次，不能省略 `--kind disk`；运行入口会拒绝用目录卷存放数据库

```bash
sb-default volume create sb-default-omp --kind disk --size 8G
sb-default up
```

`up` 在创建或启动 VM 时自动经 `sec-run` 建立 msb 原生 secret proxy；已运行时直接复用。Git 身份沿用现有 Home Manager 设置，GitHub 凭据助手由 sandbox 声明；GitHub 的 `git@github.com:` remote 在 guest 内转为 HTTPS，不需要手动登录或初始化 Git

OMP 插件由应用管理，使用 `sb-default exec omp plugin install <source>` 安装，来源参考 [OMP 插件清单](../omp/plugins/package.json)。sandbox 不安装、更新或修复插件，也不挂载宿主插件目录

## 日常运行

在项目目录执行即可，VM 停止时自动启动，OMP 在对应的 guest 目录运行

```bash
cd ~/Code/你的项目
omp-sb
omp-sb --model=mp/qoder-cn/gmodel
omp-sb -p --mode=json '使用 bash 执行 pwd，回复实际输出'
```

`omp-sb` 从运行中 VM 的挂载信息解析当前目录，交互终端自动分配 PTY，OMP 参数原样转发。当前目录必须已被 YAML 共享；未共享时明确报错，不会悄悄换到其他项目

查看配置中的模型与原始入口：

```bash
sb-default exec omp models --json
sb-default exec -t omp
sb-default exec -w /workspace bash -c 'pwd'
```

模型服务须在当前网络可达，并支持所选模型。模型列表不代表凭据套餐允许使用全部模型

## 生命周期

| 命令 | 行为 |
|---|---|
| `sb-default up` | 创建或启动，已运行则复用 |
| `sb-default exec [-t] [-w DIR] CMD…` | 注入工具环境后执行，非交互输出流式传递 |
| `sb-default shell` | 进入交互 shell |
| `sb-default status` | 查看状态 |
| `sb-default down` | 停止，保留 VM 和命名卷 |
| `sb-default rm` | 使用 msb 原生强制删除 VM，保留命名卷 |

刷新启动凭据时执行 `down`、`up`。调整 CPU、挂载、网络等 VM 规格后，删除并重建 VM；日常 OMP 配置更新不执行 `rm`

## 配置、工作区与状态

宿主 `~/Code` 映射到 `/workspace`，`~/nix-config` 按同一路径提供读写访问，供代码编辑及 Git 工作树公共目录使用。其他目录需在 YAML 中显式声明

OMP 配置位于只读 `/root/.omp/agent`，skills 与提示词位于只读 `/root/.agents`。sandbox 从已有 `home.file` 声明取得纯 store 配置，通过宿主 `~/.config/sandbox/current` 发布；guest 不跟随宿主 live-edit 软链。模型地址适配集中在 [default.nix](./default.nix)，其他 AI 模块不维护 sandbox 清单，宿主保持现有 live-edit 行为

Home Manager 只管理 `~/.config/sandbox/current` 一个发布链接，配置内容留在 Nix store。VM 挂载其真实父目录，更新链接后同一 VM 中新启动的 OMP 可以读取新配置；运行中的 OMP 是否热重载取决于应用能力

数据库、session、插件及其他 XDG 数据位于 `/data/xdg/data/omp`；状态与缓存分别位于 `/data/xdg/state/omp`、`/data/xdg/cache/omp`。`/data` 使用 VM 独占 ext4 卷，不与宿主或其他 VM 共写数据库

msb 运行数据保存在 `~/Data/sandboxes/msb`，镜像缓存位于 `~/.cache/microsandbox`。两个命令显式读取 Nix store 中的原生配置，不依赖 `~/.microsandbox/config.json`。入口同时设置原生 `MSB_HOME`，TLS 证书保存在数据根的 `tls` 子目录。Home Manager 提供相同的 `MSB_HOME`、`MSB_CONFIG_PATH`，新开终端后直接使用原生 `msb` 也读取相同配置

`/nix/store` 只读提供 Linux 工具，guest 不使用 apt 安装系统包。网络与 secret 目标以 YAML 为准；入口保留 msb 代理 CA 并供 Git 使用，不共享宿主 SSH 私钥
