# Agent Sandbox

Home Manager 提供新一代 Agent 沙箱管理 CLI `sb`（主 VM `sb-main`，基于 ADR 0002 单主 VM 加执行上下文架构）以及兼容期并存的旧命令 `sb-default` 和 `omp-sb`。

全局能力上限声明使用 [sb.yaml](./sb.yaml)，CLI 逻辑在 [sb.sh](./sb.sh)（由 [_sb.nix](_sb.nix) 注入路径并打包），guest 侧 launcher / sync / 状态查询分别在 [launcher.sh](./launcher.sh)（[_launcher.nix](_launcher.nix)）、[sync-guest.sh](./sync-guest.sh)、[guest-status.sh](./guest-status.sh)，生成配置在 [_generator.nix](_generator.nix)。旧版 VM 规格使用 [原生 msb YAML](./sb-default.yaml)，入口实现在 [_wrapper.nix](_wrapper.nix)（保留至单元 6 移除）。

sandbox 不是 AI 配置的默认组成，由 `shelken.dev.ai.sandbox.enable` 单独控制，默认关闭。开启后安装 `sb`、`sb-default`、`omp-sb`，同时引入 Linux 平台的 agent 工具闭包与 `microsandbox` CLI；关闭时这些都不进入系统

## 首次准备

宿主需要已有 `msb` 和 `sec-run`。应用本仓库的 Home Manager 配置后，为 VM 创建独占 ext4 磁盘；下面的建卷命令只执行一次，不能省略 `--kind disk`；运行入口会拒绝用目录卷存放数据库

```bash
sb-default volume create sb-default-omp --kind disk --size 8G
sb-default up
```

`up` 在创建或启动 VM 时自动经 `sec-run` 建立 msb 原生 secret proxy；已运行时直接复用。Git 身份沿用现有 Home Manager 设置，GitHub 凭据助手由 sandbox 声明；GitHub 的 `git@github.com:` remote 在 guest 内转为 HTTPS，不需要手动登录或初始化 Git

OMP 插件由 `sb sync` 按仓库 [OMP 插件清单](../omp/plugins/package.json) `bun install` 补齐（只补缺，不删除现有依赖）；sandbox 不挂载宿主插件目录

## 日常运行

在项目目录执行即可，VM 停止时自动启动，OMP 在对应的 guest 目录运行

```bash
cd ~/Code/你的项目
omp-sb
omp-sb --model=mp/qcoder-cn/gmodel
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


## 新一代主 VM 与 CLI (`sb`)

基于 [ADR 0002](../../../adr/0002-single-main-vm-execution-context.md)，所有日常执行上下文由单台主 VM `sb-main` 承载。

### 全局能力上限配置 (`sb.yaml`)

用户唯一手写的配置文件，默认路径为 `~/.config/sandbox/sb.yaml`（可通过环境变量 `SB_CONFIG` 覆盖）。用户声明能力上限后，程序自动展开环境变量、解析宿主真实路径，生成底层 microsandbox 配置与上限指纹。

```yaml
image: "ubuntu"
cpus: 4
memory: "8G"

# 命名数据卷（用于 /data，ext4 disk）
volume:
  name: "sb-main-data"
  size: "8G"

# 挂载根目录清单（宿主与 guest 内路径保持绝对一致）
mount_roots:
  - "${HOME}/Code"
  - "${HOME}/nix-config"
  - "${HOME}/.herdr/worktrees"

# 网络上限规则（公网 + DNS + 宿主端口 + 家庭网段）
network:
  policy: "public"
  allow:
    - "public"
    - "dns"
    - "host:tcp:3425"
    - "host:tcp:8080"
    - "192.168.69.46"
    # - "192.168.69.60"

# Secret 全局声明（受保护凭据及允许的目标域名/IP）
secrets:
  GITHUB_TOKEN:
    allow:
      - "github.com"
      - "api.github.com"
  CPA_PI_API_KEY:
    allow:
      - "cpa.int.ooooo.space"
  COMMANDCODE_API_KEY:
    allow:
      - "commandcode.int.ooooo.space"
  WX_PI_API_KEY:
    allow:
      - "chatapi.weixin.qq.com"
```

#### 字段说明

| 字段 | 类型 | 说明 |
|---|---|---|
| `image` | string | VM 基础镜像，默认 `ubuntu` |
| `cpus` | int | 分配给主 VM 的虚拟 CPU 核心数，默认 `4` |
| `memory` | string | 主 VM 内存规格（如 `8G`、`4G`），默认 `8G` |
| `volume.name` | string | 主数据卷名称，挂载至 guest 的 `/data`，默认 `sb-main-data` |
| `volume.size` | string | 主数据卷初始容量，默认 `8G`（自动创建为 ext4 disk 命名卷） |
| `mount_roots` | list[string] | 允许挂载的宿主根目录清单。支持 `~` 和 `${HOME}`，自动解析软链真实路径，guest 内路径与宿主保持绝对一致 |
| `network.policy` | string | 网络默认策略，默认 `public` |
| `network.allow` | list[string] | 网络上限放行规则，支持 `public`、`dns`、`host:tcp:<port>`、私网 IP 或 CIDR |
| `secrets` | map[string, object] | 全局受保护 secret 声明，映射环境变量名到允许放行的目标域名或 IP |

### 项目配置 (`.sandbox.yaml`)

位于项目仓库根目录（若无则全部采用默认值）。遵循最小权限原则在全局能力上限内精确声明三类请求：

```yaml
# .sandbox.yaml 示例

# 1. 导入宿主文件：启动时只读复制进执行上下文的 /imports，可原子改名，退出自动删除，不写回宿主
imports:
  - src: "../fake-credentials/fake-token.json"
    dst: fake-token.json

# 2. 私网网络目标：必须落在全局 sb.yaml 的 network.allow 上限内；未声明的项目无法访问私网
network:
  - "192.168.69.46"

# 3. 额外项目外目录：必须落在全局 sb.yaml 的 mount_roots 范围内，默认可写，可逐项声明只读
paths:
  - path: "~/Code/shared-lib"
    readonly: false
  - path: "~/Code/readonly-docs"
    readonly: true
  - "~/Code/another-lib:ro"   # 支持 :ro 简写
```

#### 网络授权分级（默认授权 vs 私网授权）

在 `sb-main` 执行上下文内，网络规则在每个上下文专属的网络命名空间内由 iptables 精确按源地址控制：

1. **默认授权项**（无需在 `.sandbox.yaml` 声明即全局可用）：
   - **公网目标 (`public`)**：全网公共互联网地址与外部域名解析（通过 fake-ip 代理段 `198.18.0.0/15` 及公网 IP），直接放行；
   - **DNS 解析 (`dns`)**：自动读取 guest 内 `/etc/resolv.conf` 的 nameserver（如 `172.16.0.5`）并放行 UDP/TCP 53；
   - **宿主服务端口 (`host:tcp:<port>`)**：放行 `sb.yaml` 中允许的宿主开发端口（如 `host:tcp:3425`、`host:tcp:8080`），映射到 `host.microsandbox.internal` / 宿主网关。
2. **私网受限目标**：
   - 家庭网段与私网地址（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`、`100.64.0.0/10`、`169.254.0.0/16`）默认全面拦截（REJECT）；
   - 仅当项目在 `.sandbox.yaml` 中显式声明且目标落在 `sb.yaml` 上限内时，才会在该上下文专有链中优先放行。

### `sb` 子命令与 `omp-sb`

| 命令 | 说明 |
|---|---|
| `sb up` | 确保主 VM `sb-main` 运行。首次自动创建数据卷与 VM；已存在且上限未变时直接复用；上限变化且 VM 空闲时自动重建（数据卷内容保留）；上限变化但 VM 忙碌时报错并给出运行中的上下文数 |
| `sb down` | 停止主 VM |
| `sb rm` | 删除主 VM，保留数据卷 |
| `sb sync [VM]` | 补齐沙箱内的 mise 工具与 OMP 插件（幂等，只装缺失项，不删除、不升级已有项） |
| `sb status [--json]` | 查看主 VM 状态、规格、忙碌状态、能力上限指纹一致性与缺失工具列表 |
| `sb volume …` | 原生命令数据卷管理（透传至 `msb volume`） |
| `sb run [-t] CMD…` | 在当前项目上下文内运行命令（TTY 自适应） |
| `sb shell` | 交互式进入当前项目上下文的 Bash shell（自动分配 TTY） |
| `omp-sb [参数…]` | 启动 OMP 会话。底层调用 `sb run omp "$@"`，在当前项目隔离上下文内运行 OMP |

### 上限变化处理

主 VM 创建时能力上限固定（[ADR 0006](../../../adr/0006-sandbox-razor.md)）：
- **主 VM 空闲时变更上限**：若编辑了全局 `sb.yaml`，下一次执行 `sb up`、`sb run`、`sb shell` 或 `omp-sb` 时，自动销毁旧 VM 并按当前 `sb.yaml` 重新创建启动，持久化数据卷（`/data`）完整保留。
- **主 VM 忙碌时变更上限**：运行中的上下文不受任何干扰，持续正常执行；新发起的启动命令直接报错，提示 `sb.yaml` 已变并给出运行中的上下文数，全部退出后再启动即按新上限重建。

### 共享工具登记表 (`shelken.dev.tools`)

根据 [ADR 0003](../../../adr/0003-shared-tool-single-declaration.md)，宿主与 Agent 沙箱共享的工具清单收敛为单一登记表，由 Option `shelken.dev.tools.<name>` 统一声明：

```nix
shelken.dev.tools = {
  # 1. Nix 基础工具与运行时 (package 属性名，默认等于登记名)
  rg.package = "ripgrep";
  fd = { };
  jq = { };
  gh = { };
  node.package = "nodejs";
  python3 = { };
  uv = { };

  # 2. mise 共享工具 (与 package 互斥，指定版本或规则)
  bun.mise = "1.4.2";
  codex.mise = "0.160.1";
  claude-code.mise = "2.1.304";
  omp.mise = { name = "oh-my-pi"; version = "latest"; minimum_release_age = "0h"; };
  pi.mise = { name = "npm:@earendil-works/pi-coding-agent"; version = "latest"; minimum_release_age = "0h"; };

  # 3. 配置文件 (files) 与安装后脚本 (postInstall)
  # 随工具进入沙箱发布目录，宿主照常作为 home.file；postInstall 在宿主激活和沙箱 sb sync 时分别执行
};
```

### 工具补齐与两层 mise 配置 (`sb sync`)

沙箱内的工具有两层来源：
1. **只读层 (生成层)**：由沙箱生成器解析 `shelken.dev.tools`，Nix 包合成 `guestEnv` 进沙箱 PATH；mise 条目生成 `/run/sandbox-config/current/mise.toml` 作为系统只读层。
2. **用户层 (可写层)**：位于 `/data/mise/config.toml`。Agent 在沙箱内可临时执行 `mise use -g <tool>` 安装新工具，记录在该文件中。所有执行上下文共享，且在 VM 删除重建后持久保留在数据卷中。

### 共用安装层 (ADR 0005)

mise 工具的安装产物与下载缓存不在各 VM 数据盘各存一份，而是放在宿主共用目录 `~/Data/sandboxes/mise/aarch64-linux`（`data/` 安装层 + `cache/` 下载缓存），挂进所有 VM 的固定 guest 路径 `/opt/sandbox-mise`：

- **任何 VM 首启即有完整工具**：主 VM、一次性 e2e VM、保留的 `sb-default` 都消费同一份安装层，新 VM 不再重复下载。
- **上下文内只读**：执行上下文（bubblewrap 内）对共用层只读绑定，并设置 `MISE_AUTO_INSTALL=0`；写入（安装）只经 `sb sync` 显式发生。
- **每 VM 独立状态**：mise state、shims、可写用户层 config 仍归各 VM 数据盘。
- **宿主写锁**：`sb sync` 经 flock（共用目录 `.sync.lock`）串行化，多 VM 并发 sync 安全。
- **只补缺**：不删除、不升级、不重建依赖，不区分 VM 忙闲（ADR 0006）。
- **上限指纹稳定**：指纹只含 guest 挂载声明（`/opt/sandbox-mise`），不含宿主真实路径；配置内容更新（如工具清单变化）发布到 `~/.config/sandbox/current` 后，复用中的 VM 新开上下文即可读到，不触发上限变化。

`sb sync` 负责显式补齐未安装的 mise 工具与 OMP 插件：
- **幂等执行**：仅安装缺失项，对已安装项不重新下载、不更改版本；共用的下载缓存不被清理。
- **插件清单补齐**：OMP 插件按仓库 [package.json](../omp/plugins/package.json) 清单 `bun install` 补齐（只补缺，不删除现有依赖）；沙箱内手装的插件、已从清单删除的插件不会被自动清理，需要时用 `sb volume` 清理数据盘（ADR 0006）。
- **插件凭据与私有仓库**：清单中的 `git+ssh://git@github.com/...` 源在 guest 内改写为 `https://github.com/...`，凭据由 `sb.yaml` 声明的 `GITHUB_TOKEN` secret 在网络边界替换为占位符 URL，token 不落盘、不进日志。clone 失败（如无有效凭据）只在 `sb sync` 输出中警告并继续（退出码仍为 0）；公开仓库即使无 token 也照常安装。插件状态不在 `sb status` 展示，结果只看 `sb sync` 输出。
- **不执行依赖安装脚本**：`bun install --ignore-scripts`。`node-pty` 在 Linux 无预编译产物、安装脚本会回落 `node-gyp` 编译，补齐 C 工具链的闭包增量实测 1.3 GiB（超出预算），故不引入编译器；`node-pty` 仅供 plannotator 终端桥接，不影响插件加载（见 [ADR 0005 决策 11](../../../adr/0005-shared-mise-install-layer.md)）。
- **开箱即用**：主 VM 首次全新创建时自动运行一次 `sb sync`；复用已有 VM 时 `sb run`/`sb shell`/`omp-sb` 不自动 sync。
- **Bun 下载缓存共用**：OMP 插件安装的 Bun 缓存同样落在共用层（`/opt/sandbox-mise/cache/bun-cache`），跨 VM 复用。

### 宿主控制命令防护

根据 [ADR 0003 决策 12](../../../adr/0003-shared-tool-single-declaration.md)，对于仅属于宿主管理权限的命令（如 `sb`、`spawn-subagent`、`computer-use`、`just hm/sw`），沙箱生成器在 guest PATH 注入同名桩。沙箱内部进程调用这些命令时，会立即以非零状态码退出并明确给出拒绝原因，防止 Agent 反复无谓重试。
## 配置、工作区与状态

宿主 `~/Code` 映射到 `/workspace`，`~/nix-config` 按同一路径提供读写访问，供代码编辑及 Git 工作树公共目录使用。其他目录需在 YAML 中显式声明

OMP 配置位于只读 `/root/.omp/agent`，skills 与提示词位于只读 `/root/.agents`。sandbox 从已有 `home.file` 声明取得纯 store 配置，通过宿主 `~/.config/sandbox/current` 发布；guest 不跟随宿主 live-edit 软链。模型地址适配集中在 [default.nix](./default.nix)，其他 AI 模块不维护 sandbox 清单，宿主保持现有 live-edit 行为

Home Manager 只管理 `~/.config/sandbox/current` 一个发布链接，配置内容留在 Nix store。VM 挂载其真实父目录，更新链接后同一 VM 中新启动的 OMP 可以读取新配置；运行中的 OMP 是否热重载取决于应用能力

数据库、session、插件及其他 XDG 数据位于 `/data/xdg/data/omp`；状态与缓存分别位于 `/data/xdg/state/omp`、`/data/xdg/cache/omp`。`/data` 使用 VM 独占 ext4 卷，不与宿主或其他 VM 共写数据库

msb 运行数据保存在 `~/Data/sandboxes/msb`，镜像缓存位于 `~/.cache/microsandbox`。两个命令显式读取 Nix store 中的原生配置，不依赖 `~/.microsandbox/config.json`。入口同时设置原生 `MSB_HOME`，TLS 证书保存在数据根的 `tls` 子目录。Home Manager 提供相同的 `MSB_HOME`、`MSB_CONFIG_PATH`，新开终端后直接使用原生 `msb` 也读取相同配置

`/nix/store` 只读提供 Linux 工具，guest 不使用 apt 安装系统包。网络与 secret 目标以 YAML 为准；入口保留 msb 代理 CA 并供 Git 使用，不共享宿主 SSH 私钥
