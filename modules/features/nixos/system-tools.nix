# 系统诊断工具：trace/监控/硬件信息，并把默认编辑器设为 nvim
# 所有 NixOS 主机都需要 → nixos.core
{ config, ... }:
{
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.system-tools ];

  flake.modules.nixos.system-tools =
    { lib, pkgs, ... }:
    {
      # List packages installed in system profile. To search, run:
      # $ nix search wget
      # mkOrder：与迁移前一致——基础诊断工具先于桌面机的 qemu/fhs/桌面包，
      # system-path 开 ignoreCollisions，同路径冲突时排前的包胜出
      environment.systemPackages = lib.mkOrder 600 (
        with pkgs;
        [
          gnused # GNU sed, very powerful(mainly for replacing text in files)
          # system call monitoring
          strace # system call monitoring
          ltrace # library call monitoring
          bpftrace # powerful tracing tool
          tcpdump # network sniffer
          lsof # list open files

          # system monitoring
          sysstat
          iotop
          iftop
          btop
          nmon
          sysbench

          # system tools
          psmisc # killall/pstree/prtstat/fuser/...
          lm_sensors # for `sensors` command
          ethtool
          pciutils # lspci
          usbutils # lsusb
          hdparm # for disk performance, command
          dmidecode # a tool that reads information about your system's hardware from the BIOS according to the SMBIOS/DMI standard
          parted
        ]
      );

      # replace default editor with neovim
      environment.variables.EDITOR = "nvim";
    };
}
