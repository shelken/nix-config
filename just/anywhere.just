# 装机与演练：nixos-anywhere 的 kexec 缓存、Lima 演练机；调用 just anywhere <配方>

# 模块配方默认在本文件所在目录执行，这里统一回到仓库根目录，相对路径才与根 justfile 一致
set working-directory := '..'
set positional-arguments := true

# Lima 演练机：按 hosts/vm/lima-test/nixos-anywhere-test.yaml 起一台 Ubuntu 当「待接管的 Linux」
lima-target-up name="nixos-anywhere-test":
    limactl start --name={{ name }} --tty=false hosts/vm/lima-test/nixos-anywhere-test.yaml
    @echo "目标 IP: $(just anywhere lima-target-ip {{ name }})"

# 演练机在 vzNAT 网卡（lima0）上的 IP，Mac 可直连
lima-target-ip name="nixos-anywhere-test":
    @limactl shell {{ name }} ip -4 -o addr show dev lima0 | awk '{print $4}' | cut -d/ -f1

# 删掉演练机，从头再来
lima-target-rm name="nixos-anywhere-test":
    limactl delete --force {{ name }}

# qemu 软件模拟，较慢；qemu 由 nix 临时提供，不装进系统
# x86_64 BIOS 演练机：按 hosts/vm/vps-test/nixos-anywhere-vps.yaml 起一台对齐 VPS 规格的 Ubuntu
lima-vps-up name="nixos-anywhere-vps":
    nix shell nixpkgs#qemu -c limactl start --name={{ name }} --tty=false --timeout=30m hosts/vm/vps-test/nixos-anywhere-vps.yaml
    @echo "SSH 端口: $(just anywhere lima-vps-port {{ name }})"

# 演练机映射到 Mac 本机的 SSH 端口（qemu 用户态网络，没有可直连的 IP）
lima-vps-port name="nixos-anywhere-vps":
    @limactl list {{ name }} --format '{{ "{{.SSHLocalPort}}" }}'

kexec-cache arch="aarch64" release="":
    @{{ justfile_directory() }}/utils/script/just/kexec-cache "$@"
