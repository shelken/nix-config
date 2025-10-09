{
  pkgs,
  config,
  lib,
  mylib,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.modules.desktop;
in
{
  options.shelken.modules.desktop = {
    fonts.enable = mkBoolOpt false "Rich Fonts - Add NerdFonts Icons, emojis & CJK Fonts";
  };
  config.fonts.packages =
    with pkgs;
    mkIf cfg.fonts.enable [
      # icon fonts
      material-design-icons
      font-awesome

      # 思源系列字体是 Adobe 主导的。其中汉字部分被称为「思源黑体」和「思源宋体」，是由 Adobe + Google 共同开发的
      source-sans # 无衬线字体，不含汉字。字族名叫 Source Sans 3 和 Source Sans Pro，以及带字重的变体，加上 Source Sans 3 VF
      source-serif # 衬线字体，不含汉字。字族名叫 Source Code Pro，以及带字重的变体
      source-han-sans # 思源黑体
      source-han-serif # 思源宋体

      # nerdfonts
      # https://github.com/NixOS/nixpkgs/blob/nixos-unstable-small/pkgs/data/fonts/nerd-fonts/manifests/fonts.json
      nerd-fonts.symbols-only # symbols icon only
      nerd-fonts.fira-code
      nerd-fonts.jetbrains-mono

      # julia-mono
      # dejavu_fonts

      # https://github.com/subframe7536/Maple-font
      # https://search.nixos.org/packages?channel=unstable&from=0&size=50&sort=relevance&type=packages&query=maple-
      # maple-mono-SC-NF
    ];
}
