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
            grid = config.boot.kernelPackages.nvidiaPackages.grid_17_6.overrideAttrs (old: {
              # 驱动的 conftest 不带 -std，gcc 15 起默认 gnu23，内核头文件在 gnu23 下编不过，
              # 探测全部失败、模块误判成不支持这个内核；内核自己用 gnu11
              env = (old.env or { }) // {
                NIX_CFLAGS_COMPILE = "-std=gnu11";
              };
              # nixpkgs 聚合内核模块时要求每个外部模块带 kmodigest 生成的 <模块>.ko.cer，
              # 通常由内核的 modules_install 顺带生成；驱动的 builder 直接拷 .ko，跳过了这一步
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.buildPackages.kmodigest ];
              # builder 用一次 patchelf 同时改 interpreter 与 rpath，会把 LOAD 段改成重叠、.dynamic 落进只读页，
              # ld.so 启动即崩（NixOS/nixpkgs#576412）：从未改动的 origBin 副本重做，拆成两次调用
              postInstall = toString (old.postInstall or "") + ''
                find "$bin/lib/modules" -name '*.ko' -exec kmodigest {} \;
                for f in "$bin"/origBin/*; do
                  i="$bin/bin/$(basename "$f")"
                  install -m755 "$f" "$i"
                  patchelf --set-rpath "$out/lib:$libPath" "$i"
                  patchelf --interpreter "$(cat "$NIX_CC/nix-support/dynamic-linker")" "$i"
                done
              '';
            });
          in
          grid // { mod = grid.bin; };
        open = false;
        nvidiaSettings = false;
      };
      # NixOS 只有声明了 nvidia 视频驱动才会构建并加载内核模块
      services.xserver.videoDrivers = [ "nvidia" ];
      boot.blacklistedKernelModules = [ "nouveau" ];

      # nvidia-gridd 由 vgpu4nixos 提供；授权令牌由 fastapi-dls 签发，启动时从这个固定路径读取
      # gridd 只认 744（NVIDIA 授权文档的要求）；sops 默认的 0400 会被当成 Unreadable，节点一直未授权
      sops.secrets.nvidia-client-token = {
        path = "/etc/nvidia/ClientConfigToken/client_configuration_token.tok";
        mode = "0744";
      };

      hardware.nvidia-container-toolkit = {
        enable = true;
        # device plugin 经 NVIDIA_VISIBLE_DEVICES 传 GPU UUID，cdi 模式按名字在规格里找设备
        device-name-strategy = "uuid";
      };
      # 默认 auto 模式在创建容器时现场生成 CDI 规格，靠 ldcache 找驱动库，NixOS 上找不到；
      # 改用 cdi-generator 预先生成的 /var/run/cdi 规格。nixpkgs 只在启用 docker 时写这份配置
      environment.etc."nvidia-container-runtime/config.toml".text = ''
        [nvidia-container-runtime]
        mode = "cdi"
      '';
      # k3s 发现 PATH 里的 nvidia-container-runtime 时，自动加一个名为 nvidia 的 containerd runtime，
      # 与集群 RuntimeClass 的 handler 同名，集群清单不用改
      systemd.services.k3s.path = [
        (lib.getOutput "tools" config.hardware.nvidia-container-toolkit.package)
      ];
    };
}
