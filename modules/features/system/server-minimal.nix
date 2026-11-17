# server-minimal：关掉 NixOS 默认为本机交互准备的东西 → nixos.server
# 服务器由 deploy-rs 推送、不在本机跑 nix run / nixos-rebuild，这些只占闭包
{ config, ... }:
{
  flake.modules.nixos.server.imports = [ config.flake.modules.nixos.server-minimal ];

  flake.modules.nixos.server-minimal = {
    # 默认把整份 nixpkgs 源码钉进 registry 与 NIX_PATH，约 200 MiB
    nixpkgs.flake = {
      setFlakeRegistry = false;
      setNixPath = false;
    };
    # nixos-rebuild、nixos-install、nixos-enter、nixos-generate-config 等
    system.disableInstallerTools = true;
    # 重装手册的首启验收用它，只是一个小脚本
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
