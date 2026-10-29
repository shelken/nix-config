# 虚拟机 Disko 分区配置

定义虚拟机主机的声明式磁盘分区布局

## 配置说明

- `general.nix`：通用虚拟机磁盘布局，针对 `/dev/sda` 声明 GPT 分区表，包含 500M EFI 系统分区（vfat，挂载于 `/boot`）与根分区（ext4，挂载于 `/`）

## 使用场景

在对应 NixOS 虚拟机主机配置中（如 `hosts/vm/` 或相关主机 `default.nix`）通过 `disko` 模块引入，配合 `just gen-image` 或系统安装流程声明式格式化磁盘
