# nixpkgs overlays：全部平台统一注入
# overlays 里的文件以 specialArgs 为参数（mylib、dotfiles 等）
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.overlays ];
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.overlays ];

  flake.modules.darwin.overlays = args: {
    nixpkgs.overlays = import ../../../overlays args;
  };

  flake.modules.nixos.overlays = args: {
    nixpkgs.overlays = import ../../../overlays args;
  };
}
