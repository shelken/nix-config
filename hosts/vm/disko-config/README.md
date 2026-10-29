# 虚拟机 Disko 分区配置

定义虚拟机主机的声明式磁盘分区布局

## 配置说明

- `general.nix`：通用虚拟机磁盘布局，针对 `/dev/sda` 声明 GPT 分区表，包含 500M EFI 系统分区（vfat，挂载于 `/boot`）与根分区（ext4，挂载于 `/`）

## 使用场景

在对应 NixOS 虚拟机主机配置中通过 `disko` 模块引入，在系统安装部署阶段（如使用 `disko-install` 或 `nix run github:nix-community/disko`）进行声明式磁盘分区与格式化
