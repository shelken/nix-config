# niri 合成器：系统侧启用与包选择，用户态会话脚本与快捷键
# NixOS 桌面机（gui 角色）→ nixos.gui；HM 部分经同名挂接进入
{ config, ... }:
{
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.niri ];

  flake.modules.nixos.niri =
    { niri, pkgs, ... }:
    {
      imports = [
        niri.nixosModules.niri
        { programs.niri.enable = true; }
      ];

      # niri-flake 默认包依赖 nixpkgs 已移除的 libdisplay-info_0_2 且断言版本为 0.2.0，
      # 上游尚未跟进，所以改用 nixpkgs 自带的 niri。
      programs.niri.package = pkgs.niri;
    };

  flake.modules.homeManager.niri =
    {
      niri,
      pkgs,
      ...
    }:
    {
      imports = [ (import ./niri/_keybindings.nix niri) ];

      home.packages = with pkgs; [
        # Niri v25.08 will create X11 sockets on disk, export $DISPLAY, and spawn `xwayland-satellite` on-demand when an X11 client connects
        xwayland-satellite
      ];

      # NOTE: this executable is used by greetd to start a wayland session when system boot up
      # with such a vendor-no-locking script, we can switch to another wayland compositor without modifying greetd's config in NixOS module
      home.file.".wayland-session" = {
        source = pkgs.writeScript "init-session" ''
          # trying to stop a previous niri session
          systemctl --user is-active niri.service && systemctl --user stop niri.service
          # and then we start a new one
          /run/current-system/sw/bin/niri-session
        '';
        executable = true;
      };
    };
}
