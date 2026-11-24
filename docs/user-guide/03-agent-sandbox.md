# Agent 沙箱日常使用

机制、术语与配置字段见 [沙箱 README](../../modules/features/ai/sandbox/README.md)，完整子命令运行 `sb --help` 查看

## 首次启用

1. 应用配置并新开终端：
   ```bash
   just hm
   ```
2. 进入位于挂载根（默认 `~/Code`、`~/nix-config`）内的项目目录，启动 Agent：
   ```bash
   cd ~/Code/my-app
   omp-sb            # 启动 OMP，参数原样透传；启动 pi 用 pi-sb
   ```

首次启动会自动建卷、拉起主 VM 并执行一次 `sb sync`，耗时数分钟；如需快速验证可用性，可运行 `omp-sb --model=<provider/model> -p '只回复 OK'`

## 日常操作

### 多开、worktree 与临时命令

- **多开**：在不同终端分别运行 `omp-sb` 或 `pi-sb` 即可；同项目并发时避免同时改同一文件
- **worktree**：直接进入 `~/Code/worktrees/<项目>/<分支>` 启动，要求 worktree 与主仓库都在挂载根内
- **临时命令**：`sb run git status` 跑单条命令，`sb shell`（或 `sb run -t bash`）进入当前项目上下文

### 误删项目文件恢复

每次启动前宿主都会建一个 APFS 本地快照，发现误删需尽快恢复（磁盘紧张时系统会自动回收）：

```bash
tmutil listlocalsnapshots /
```

可在 Finder 打开项目目录后通过 Time Machine 恢复，或用命令行只读挂载快照拷回：

```bash
mkdir /tmp/snap
sudo mount_apfs -o rdonly -s com.apple.TimeMachine.<时间>.local /System/Volumes/Data /tmp/snap
cp -R /tmp/snap/Users/<你>/Code/<项目>/<文件> ~/Code/<项目>/
sudo umount /tmp/snap
```

## 项目授权（`.sandbox.yaml`）

项目需要宿主凭据、私网服务或项目外目录时，在项目根创建 `.sandbox.yaml`：

```yaml
imports:
  - src: ~/.kube/home-ops.yaml
    target: ~/.kube/home-ops.yaml
network:
  - "192.168.1.10" # 或 IP:端口
paths:
  - ~/Code/shared-lib
  - ~/Code/design-docs:ro
```

写完或修改后先检查授权清单，再批准，否则启动直接报错：

```bash
sb plan
sb trust
```

## 补充工具

- **单项目工具**：写入项目 `mise.toml`，在沙箱内执行：
  ```bash
  sb run bash -c 'mise trust && mise install'
  ```
- **全局工具**：在 [ai-tools.nix](../../modules/features/ai/ai-tools.nix) 或 [tools-base.nix](../../modules/features/dev/tools-base.nix) 中登记 `shelken.dev.tools`：
  ```nix
  shelken.dev.tools = {
    yq.package = "yq-go";
    bun.mise = "1.4.2";
  };
  ```
  随后应用配置并同步到沙箱（宿主侧 mise 工具另需 `mise install`）：
  ```bash
  just hm
  sb sync
  ```

## 改配置与运维

改 OMP、pi 配置或能力上限 [sb.yaml](../../modules/features/ai/sandbox/sb.yaml) 后，在宿主执行：

```bash
just hm
sb sync            # 改了插件或 mise 工具清单时补齐
```

改完 `sb.yaml` 需退出运行中的 Agent 后再启动，以触发主 VM 重建

```bash
sb status          # 查看主 VM 状态、上限是否一致与缺失工具
sb plan            # 查看当前项目实际授权与批准状态
sb down            # 停止主 VM（空闲超时也会自动停止）
sb rm              # 删除主 VM（保留数据卷；--force 强删）
```
