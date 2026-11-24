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
      launchd.agents.nix-gc.config.ProgramArguments = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
        lib.mkForce [
          "/nix/var/nix/profiles/default/bin/nix-collect-garbage"
          "--delete-older-than"
          "7d"
        ]
      );
    };
}
