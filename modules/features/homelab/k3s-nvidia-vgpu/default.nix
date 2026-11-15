# k3s-nvidia-vgpu：NVIDIA vGPU（GRID）guest 驱动与 k3s 的 nvidia 容器运行时，只给 PVE 上分到 mdev 的 worker 用
# 可选功能：homelab-1 主机直接导入；不要与桌面用的 features/nixos/nvidia.nix 同时导入
# 取舍与期限见 ./README.md
{ inputs, ... }:
{
  flake.modules.nixos.k3s-nvidia-vgpu =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ inputs.vgpu4nixos.nixosModules.guest ];

      # GRID 17.6 是已停止维护的 550 驱动，编不过 6.15 以后的内核；硬件是 Pascal 消费卡，
      # 整卡直通不可用、vGPU 无法再升级。6.12 LTS 维护到 2028-12，之后这套硬件的 vGPU 路线到头
      boot.kernelPackages = pkgs.linuxPackages_6_12;
      hardware.nvidia = {
        # nixpkgs 的 nvidia 模块从 package.mod 取内核模块；vgpu4nixos 的包还没有这个属性，
        # 它把模块装在 bin 输出的 lib/modules 下
        package =
          let
            grid = config.boot.kernelPackages.nvidiaPackages.grid_17_6;
          in
          grid // { mod = grid.bin; };
        open = false;
        nvidiaSettings = false;
      };
      # NixOS 只有声明了 nvidia 视频驱动才会构建并加载内核模块
      services.xserver.videoDrivers = [ "nvidia" ];
      boot.blacklistedKernelModules = [ "nouveau" ];

      hardware.nvidia-container-toolkit.enable = true;
      # k3s 发现 PATH 里的 nvidia-container-runtime 时，自动加一个名为 nvidia 的 containerd runtime，
      # 与集群 RuntimeClass 的 handler 同名，集群清单不用改
      systemd.services.k3s.path = [
        (lib.getOutput "tools" config.hardware.nvidia-container-toolkit.package)
      ];
    };
}
