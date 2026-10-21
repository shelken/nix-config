{ niri, pkgs, ... }:
{
  imports = [
    ./base
    ../base

    niri.nixosModules.niri
    ./desktop
  ]
  ++ [ { programs.niri.enable = true; } ];

  # niri-flake 默认包依赖 nixpkgs 已移除的 libdisplay-info_0_2 且断言版本为 0.2.0，
  # 上游尚未跟进，所以改用 nixpkgs 自带的 niri。
  programs.niri.package = pkgs.niri;
}
