set working-directory := '..'
set positional-arguments := true

[doc('下载并缓存 nixos-anywhere 的 kexec 安装环境，stdout 只输出缓存文件路径')]
kexec-cache arch="aarch64" release="":
    @{{ justfile_directory() }}/utils/script/just/kexec-cache "$@"

# 与 flake 的 systemd 同一发布线：disko 用目标系统的 udevadm settle，安装环境太旧时分区链接来不及出现（见 hosts/vps/vps-cc/README.md）
kexecRelease := "nixos-26.05"

[doc('阶段一：把目标 kexec 进安装环境，磁盘不动；之后若卡在重连就 Ctrl-C')]
kexec host target:
    nixos-anywhere -f .#{{ host }} --target-host root@{{ target }} --phases kexec --kexec-extra-flags '-c' \
      --kexec "$(just anywhere::kexec-cache "$(nix eval --raw .#nixosConfigurations.{{ host }}.pkgs.stdenv.hostPlatform.parsed.cpu.name)" {{ kexecRelease }})"

[doc('阶段二：按主机声明写好安装环境的 substituters，再 disko、install、reboot')]
install host target extra="":
    @{{ justfile_directory() }}/utils/script/just/anywhere-install "$@"
