# k3s-nvidia-vgpu

PVE 虚拟机里的 NVIDIA vGPU guest 驱动（GRID 17.6，经 [vgpu4nixos](https://github.com/shelken/vgpu4nixos)）加 k3s `nvidia` 运行时，仅 `homelab-1` 导入

## 约束与取舍

- 宿主物理卡为 Pascal 消费卡（GTX 1050 Ti Mobile），整卡直通报错 `no device found` 不可行，只能解锁跑 vGPU 17.x
- 不升级 vGPU：18 已 EOL，19 对 Pascal 不可靠，20 起无法解锁
- 17.6 驱动（550 系列，无 `vgpuPatcher` 支持）编不过 6.15+ 内核，内核锁死 `linuxPackages_6_12`（维护至 2028-12）
- 禁止在 PVE 宿主运行 `nvidia-smi` 等 nvidia 命令，会卡死
