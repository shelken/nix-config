# nixpkgs overlays：全部平台统一注入（modules/base/overlays.nix 迁入）
# overlays 里的文件以 specialArgs 为参数（mylib、dotfiles 等），与原 modules/base/overlays.nix 相同
{
  flake.modules.darwin.overlays = args: {
    nixpkgs.overlays = import ../../../overlays args;
  };

  flake.modules.nixos.overlays = args: {
    nixpkgs.overlays = import ../../../overlays args;
  };
}
