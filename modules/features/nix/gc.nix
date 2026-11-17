# Nix 垃圾回收：root 清系统代数，用户清自己的 home-manager 与 nix profile 代数，保留 7 天
# root 的 GC 按设计不碰用户家目录里的 profile（NixOS/nix#8508），所以两层都要
{ config, lib, ... }:
{
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.nix-gc ];
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.nix-gc ];

  flake.modules.nixos.nix-gc =
    { myvars, ... }:
    {
      nix.gc = {
        automatic = lib.mkDefault true;
        dates = lib.mkDefault "weekly";
        options = lib.mkDefault "--delete-older-than 7d";
      };
      # 用户级 GC 是 systemd 用户定时器，不登录的服务器要 linger 才会触发
      users.users.${myvars.username}.linger = true;
    };

  # 不走 nix.gc：它要求 nix.enable=true，与 Determinate 接管 nix.conf 冲突
  flake.modules.darwin.nix-gc = {
    shelken.tasks.nix-gc = {
      when = "3:15";
      user = false;
      # --quiet 去掉逐条 deleting 输出：一次几千行，日志一个月涨到 8MB；汇总行走 stdout 不受影响
      script = ''
        exec /nix/var/nix/profiles/default/bin/nix-collect-garbage --quiet --delete-older-than 7d
      '';
    };
  };

  flake.modules.homeManager.nix-gc =
    { pkgs, ... }:
    {
      nix.gc = {
        automatic = true;
        options = "--delete-older-than 7d";
      };
      # HM 在 launchd 上把 options 整串当一个参数传，nix-collect-garbage 会报 unrecognised flag；
      # 顺带改用 Determinate 的 nix，不再把 nixpkgs 的 nix 带进闭包
      launchd.agents.nix-gc.config.ProgramArguments = lib.mkIf pkgs.stdenv.isDarwin (
        lib.mkForce [
          "/nix/var/nix/profiles/default/bin/nix-collect-garbage"
          "--delete-older-than"
          "7d"
        ]
      );
    };
}
