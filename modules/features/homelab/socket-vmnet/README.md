# socket-vmnet

以 root 用 launchd 常驻 nixpkgs 的 `socket_vmnet`（bridged），Lima 实例用 `networks: - socket: <路径>` 连接（非托管模式）。可选功能，只有 sakamoto、yuuko 导入

- 为什么常驻：Lima 托管模式要求二进制整条路径归 root、组不可写，`/nix/store`（属组 `nixbld`、组可写）不满足，所以不再由 Lima 按需 `sudo` 拉起，也不需要 `/etc/sudoers.d/lima` 与 `/opt/socket_vmnet`
- 选项 `shelken.socketVmnet.interface`：桥接的宿主网卡，默认值在 `vars/default.nix` 的 `socketVmnet`
- socket 为 `/var/run/socket_vmnet.bridged.<网卡>`（上游 plist 的约定），`hosts/k8s/lima.nix` 从同一处 `vars` 取路径
- 参数对照上游 `launchd/io.github.lima-vm.socket_vmnet.bridged.en0.plist`；日志放平到 `/var/log/socket_vmnet.bridged.<网卡>.{stdout,stderr}`；socket 属组用 `socket_vmnet` 的默认值 `staff`
- 必须在 Lima 节点启动前生效：socket 不存在时 `limactl start` 会失败
