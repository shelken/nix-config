{ config, ... }:
{
  flake.modules.nixos.server.imports = [ config.flake.modules.nixos.server-minimal ];

  flake.modules.nixos.server-minimal = {
    nixpkgs.flake = {
      setFlakeRegistry = false;
      setNixPath = false;
    };
    system.disableInstallerTools = true;
    system.tools.nixos-version.enable = true;
    documentation.enable = false;
    # 不受上一行控制，默认仍装 man-db 与 groff（约 11 MiB），而手册页已不存在
    documentation.man.enable = false;
  };

  flake.modules.homeManager.server-minimal = {
    programs.man.enable = false;
    manual.manpages.enable = false;
  };
}
