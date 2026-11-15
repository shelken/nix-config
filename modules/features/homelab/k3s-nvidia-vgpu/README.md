# k3s-nvidia-vgpu

PVE 虚拟机里的 NVIDIA vGPU guest 驱动（GRID 17.6，经 [vgpu4nixos](https://github.com/mrzenc/vgpu4nixos)）加 k3s 的 `nvidia` 容器运行时。可选功能，只有 homelab-1 导入

## 取舍

- 宿主 PVE 的物理卡是 Pascal 消费卡（GTX 1050 Ti Mobile），靠解锁补丁跑 vGPU 17.6；整卡直通试过，`no device found`，不可行
- 不升级 vGPU：18 已 EOL，19 对 Pascal 不可靠，20 起无法解锁
- 驱动固定 17.6（550 系列，上游已停维护），编不过 6.15 以后的内核，所以内核固定 `linuxPackages_6_12`。6.12 LTS 维护到 2028-12，之后这条路线到头

## 依赖

- 宿主 vGPU 版本必须是 17.x；guest 驱动由 vgpu4nixos 从 Google Cloud 公开下载
- 授权由 sakamoto 上的 fastapi-dls 签发；guest 的 `nvidia-gridd` 从 `/etc/nvidia/ClientConfigToken/` 读取令牌
- 集群的 `RuntimeClass nvidia` 的 handler 是 `nvidia`，对应 k3s 在 PATH 里发现 `nvidia-container-runtime` 时生成的 runtime

vgpu4nixos 对 17.6 没有 vGPU-Unlock-patcher 支持（`vgpuPatcher = null`），无法用补丁适配新内核

不要在 PVE 宿主上运行 `nvidia-smi` 等 nvidia 命令：会卡死
