# Agent 沙箱日常使用

让 OMP 在一台 Linux 虚拟机里干活：它只看得到当前项目，访问不了家里其他服务，`rm -rf` 删不到别的仓库。宿主 macOS 不受影响

机制和配置字段见 [沙箱 README](../../modules/features/ai/sandbox/README.md)，设计原因见 [ADR 0002](../adr/0002-single-main-vm-execution-context.md)

## 先认识三个词

| 词              | 是什么                                                                                      |
| --------------- | ------------------------------------------------------------------------------------------- |
| 主 VM `sb-main` | 一台常驻的 Linux 虚拟机，所有 Agent 都跑在它里面                                            |
| 执行上下文      | 每次 `omp-sb` 新开的隔离环境，只绑定当前项目，退出即销毁                                    |
| 能力上限        | `sb.yaml` 声明的最大权限（可挂载的目录、可访问的私网、可用的 secret），项目只能在上限内申请 |

## 场景一：第一次用起来

1. 在主机的 Home Manager 配置里打开开关（`mio` 已开），例如 `hosts/<机器>/home.nix`：
   ```nix
   shelken.dev.ai.sandbox.enable = true;
   ```
2. 应用配置，然后新开一个终端
   ```bash
   just hm
   ```
3. 进入任意项目，启动 OMP
   ```bash
   cd ~/Code/my-app
   omp-sb
   ```

第一次启动会自动完成三件事，耗时几分钟：创建数据卷、创建主 VM、执行一次 `sb sync` 安装 omp、pi、codex 等工具。之后再启动只需几秒

`omp-sb` 的参数原样转给 OMP：

```bash
omp-sb --model=mp/qcoder-cn/gmodel
# 只是测试沙箱能不能用时，指定便宜模型
omp-sb --model=cpa/gpt-5.6-luna -p '只回复 OK'
```

家里的模型服务（`192.168.69.46:443`）由 `sb.yaml` 的 `network.default_grant` 对所有项目默认放行，不需要在项目里声明

项目必须位于挂载根内（默认 `~/Code`、`~/nix-config`、`~/.herdr/worktrees`），否则启动时报错

## 场景二：同时开多个 Agent

每个终端执行一次 `omp-sb` 即可，新开的不会打断已在运行的

```bash
# 终端 1
cd ~/Code/my-app && omp-sb
# 终端 2：另一个项目
cd ~/Code/blog && omp-sb
# 终端 3：同一个项目再开一个
cd ~/Code/my-app && omp-sb
```

- 不同项目的 Agent 互相看不到对方的目录
- 同一项目的多个 Agent 共用同一份项目文件，注意不要同时改同一个文件
- 所有 Agent 共用一份 OMP 数据（会话、插件、数据库），和宿主上同时开多个 OMP 的效果一样

在 worktree 里运行也一样：

```bash
cd ~/.herdr/worktrees/my-app/feature-x
omp-sb
```

主仓库的 `.git` 会自动挂进来，Agent 可以正常 `git status`、`git commit`，提交在宿主上立即可见

## 场景三：项目需要凭据、私网服务或项目外目录

在项目根目录写 `.sandbox.yaml`，下次启动生效：

```yaml
# 把宿主文件复制进沙箱，src 必须在 sb.yaml 的 import_sources 内
imports:
  - src: ~/.kube/home-ops.yaml
    target: ~/.kube/home-ops.yaml # 上下文里的路径，~ 是上下文的家目录

# 允许访问家里的服务（必须在 sb.yaml 的 network.allow 里）
network:
  - "192.168.69.46"

# 挂载项目外的目录（必须在挂载根内）
paths:
  - ~/Code/shared-lib # 可写
  - ~/Code/design-docs:ro # 只读
```

| 字段      | 不写时                                            | 作用                                                              |
| --------- | ------------------------------------------------- | ----------------------------------------------------------------- |
| `imports` | 不导入                                            | 启动时复制到 `target`，退出时删除；Agent 改了也不会写回宿主。`target` 所在目录在上下文里只剩导入的文件 |
| `network` | 私网全部拒绝（`sb.yaml` 的 `default_grant` 除外） | 只放行列出的私网 IP 或 `IP:端口`；公网、DNS、宿主开发端口一直可用 |
| `paths`   | 只挂当前项目                                      | 额外挂载的目录，加 `:ro` 为只读                                   |

申请超出上限时，启动直接报错，例如：

```
[-] 错误: .sandbox.yaml 中声明的私网目标 192.168.69.60 超出能力上限 (sb.yaml network.allow 未授权该目标)
```

这时去改能力上限，见场景五

GitHub token 等 secret 不需要写进 `.sandbox.yaml`：沙箱里只有占位符，请求发往 `sb.yaml` 允许的域名时才在出口替换成真实值

## 场景四：沙箱里缺工具

Agent 在沙箱内不能安装工具。长期需要的工具登记到共享工具表，宿主和沙箱同时获得：

1. 在 `modules/features/ai/tools.nix`（AI 工具）或 `modules/features/dev/tools-base.nix`（基础 CLI）里加一条
   ```nix
   shelken.dev.tools = {
     yq.package = "yq-go";   # Nix 提供
     bun.mise = "1.4.2";     # mise 提供，可写版本号
   };
   ```
2. 应用配置，并把工具装进沙箱
   ```bash
   just hm
   sb sync
   ```

- Nix 工具在 `just hm` 后新开的上下文里就能用
- mise 工具要等 `sb sync` 装完；宿主上同样要执行 `mise install`
- `sb sync` 只补缺，不升级、不删除；Agent 运行中也可以执行

## 场景五：改能力上限，重建或排查问题

### 改 `sb.yaml`

能力上限的源文件是 `modules/features/ai/sandbox/sb.yaml`，改完执行 `just hm`。下一次 `omp-sb` 时：

- 没有 Agent 在运行：自动按新上限重建主 VM，数据卷保留
- 还有 Agent 在运行：新的启动直接报错，正在运行的不受影响。全部退出后再启动即可

### 看状态

```bash
sb status
```

```
VM 名称: sb-main
VM 状态: Running
VM 规格: cpus=4, memory=8G
运行指纹: 3f2a…
当前指纹: 3f2a…
上限一致: consistent
运行状态: busy
缺失工具: 无
```

`上限一致` 显示 `inconsistent` 表示 `sb.yaml` 已改、主 VM 还没重建；`缺失工具` 不为「无」时执行 `sb sync`

### 看当前项目拿到了哪些授权

在项目目录里执行，不会创建 VM，也不会启动 Agent：

```bash
sb plan
```

```
项目根: /Users/me/Code/my-app
额外路径:
  无
导入文件:
  /Users/me/.kube/home-ops.yaml → ~/.kube/home-ops.yaml
放行的私网目标:
  192.168.69.46:443（sb.yaml 默认放行）
放行的宿主端口:
  host:tcp:3425
```

沙箱里连不上某个内网地址、读不到某个文件时，先看这里有没有列出。`.sandbox.yaml` 写错或超出上限时它会和启动一样报错

### 进沙箱看看

```bash
sb shell            # 在当前项目的上下文里开一个 bash
sb run git status   # 只跑一条命令
```

### 停止、删除

```bash
sb down            # 停止主 VM，下次 omp-sb 自动启动
sb rm              # 删除主 VM，数据卷保留；有 Agent 在运行时会拒绝
sb rm --force      # 强制删除，会打断所有 Agent
```

### 常见报错

| 报错                                            | 原因                          | 处理                                                           |
| ----------------------------------------------- | ----------------------------- | -------------------------------------------------------------- |
| `当前项目根目录 … 超出沙箱能力上限`             | 项目不在挂载根内              | 把项目移到 `~/Code` 下，或在 `sb.yaml` 的 `mount_roots` 加目录 |
| `worktree 的 git common dir … 超出沙箱能力上限` | worktree 的主仓库不在挂载根内 | 同上，把主仓库所在目录加进 `mount_roots`                       |
| `sb.yaml 已变，主 VM 有 N 个执行上下文在运行`   | 改了上限但还有 Agent 在跑     | 退出这些 Agent 后重新启动                                      |
| `.sandbox.yaml 中声明的导入文件不存在`          | `imports` 路径写错            | 相对路径以项目根为起点，`~` 表示家目录                         |
| `导入文件 … 超出能力上限`                       | `src` 不在 `import_sources` 内 | 把所在目录加进 `sb.yaml` 的 `import_sources`                   |
| 在沙箱里执行 `sb`、`just` 等命令被拒绝          | 这些命令只能在宿主上执行      | 回到宿主终端执行                                               |
