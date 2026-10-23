# Rich Fonts：Nerd Fonts、CJK、图标字体
# darwin 由 desktop 角色、NixOS 由 gui 角色自带（ling 停在 gui，因此没有字体）
{ config, ... }:
let
  packages =
    pkgs: with pkgs; [
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
      nerd-fonts.iosevka

      # julia-mono
      # dejavu_fonts

      # https://github.com/subframe7536/Maple-font
      # https://search.nixos.org/packages?channel=unstable&from=0&size=50&sort=relevance&type=packages&query=maple-
      maple-mono.NF-CN-unhinted
    ];
in
{
  flake.modules.darwin.desktop.imports = [ config.flake.modules.darwin.fonts ];
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.fonts ];

  flake.modules.darwin.fonts =
    { pkgs, ... }:
    {
      fonts.packages = packages pkgs;
    };

  flake.modules.nixos.fonts =
    { pkgs, ... }:
    {
      fonts.packages = packages pkgs;
    };
}
