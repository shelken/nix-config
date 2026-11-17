# lima-host

Lima 宿主（sakamoto、yuuko）的功能：桥接网卡 `socket_vmnet`、实例声明、附加盘软链与自启动。可选功能，宿主在 `imports` 里导入 `lima-host`，并设置选项：

| 选项                            | 说明                                                                                  |
| ------------------------------- | ------------------------------------------------------------------------------------- |
| `shelken.limaHost.node`         | 宿主承载的节点，即 `nixosConfigurations` 里的名字，也是 Lima 实例名（`sakamoto-k8s`） |
| `shelken.limaHost.externalDisk` | 可选。实例依赖的外接盘挂载点（`/Volumes/sakamoto-data`）；不设表示没有依赖（yuuko）   |

## 系统侧（`darwin.nix`）：socket_vmnet

以 root 用 launchd 常驻 nixpkgs 的 `socket_vmnet`（bridged），Lima 实例用 `networks: - socket: <路径>` 连接（非托管模式）

- 为什么常驻：Lima 托管模式要求二进制整条路径归 root、组不可写，`/nix/store`（属组 `nixbld`、组可写）不满足，所以不再由 Lima 按需 `sudo` 拉起，也不需要 `/etc/sudoers.d/lima` 与 `/opt/socket_vmnet`
- 桥接网卡与 socket 路径在 `vars/default.nix` 的 `socketVmnet`：socket 为 `/var/run/socket_vmnet.bridged.<网卡>`（上游 plist 的约定），`hosts/k8s/lima.nix` 从同一处取
- 参数对照上游 `launchd/io.github.lima-vm.socket_vmnet.bridged.en0.plist`；日志放平到 `/var/log/socket_vmnet.bridged.<网卡>.{stdout,stderr}`；socket 属组用 `socket_vmnet` 的默认值 `staff`
- 必须在 Lima 节点启动前生效：socket 不存在时 `limactl start` 会失败

## 用户侧（`home.nix`）

- **`~/.lima/<节点>/lima.yaml`**：节点只暴露数据 `nixosConfigurations.<节点>.config.system.build.limaConfig`，宿主用自己的 `pkgs.formats.yaml` 生成，链到 Nix store。不用节点的构建产物：那是 aarch64-linux 的 derivation，在 Mac 上构建要 Linux builder
- **`~/.lima/_disks`**（仅设了 `externalDisk`）：软链到 `<externalDisk>/k8s/lima/_disks`，Lima 附加盘放在外接盘上
- **自启动 agent**（`space.ooooo.lima-host`，日志 `~/Library/Logs/lima-host.log`）：`RunAtLoad` 执行 `limactl start --tty=false <节点>`
  - 实例已在运行：`limactl` 提示并以 0 退出，不做任何事
  - 设了 `externalDisk`：先检查它已挂载，没挂上就记日志、以 0 退出，并配 `StartOnMount`，盘挂上时再来一次
  - 不设 `KeepAlive`：失败不反复重试
- `limactl` 用 Homebrew 装的那份（`modules/features/dev/lima.nix`，路径取 `homebrew.prefix`），不引入第二份 Lima

### 为什么 agent 重载不会杀掉虚拟机

Home Manager 改 plist 时会 `bootout` 旧 agent，launchd 会清理它的进程组。所以不能让 `limactl` 常驻（`--foreground`），而是让它起完就退出：

- `limactl start` 用 `Setpgid: true` 把 hostagent（`limactl hostagent`，虚拟机就跑在它里面）放进**自己的进程组**，输出重定向到实例目录下的文件，随后 `limactl start` 等到就绪就退出（Lima 2.1.1：`pkg/instance/start.go`、`pkg/executil/opts_others.go`）
- 即使 `limactl start` 还在等待就绪时被 `bootout`，hostagent 也不在被清理的进程组里
- `AbandonProcessGroup = true` 是第二道保险：launchd 不清理 agent 退出后遗留的任何进程

### 实例声明是只读的

`lima.yaml` 是 store 里的只读文件：`limactl start/stop/list/shell` 只读取它。`limactl edit`、`limactl start --cpus ...` 这类会改配置的命令会因权限被拒（`permission denied`），不会损坏文件。改配置只改 Nix（`hosts/k8s/`），见 `hosts/k8s/README.md`
