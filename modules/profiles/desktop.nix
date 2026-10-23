# desktop：gui + 日常桌面机共有的功能（容器、字体、lima 等）；ling 这类精简桌面机停在 gui
{ config, ... }:
let
  inherit (config.flake.modules) darwin;
in
{
  flake.modules.darwin.desktop = {
    imports = [ darwin.gui ];
    shelken.modules.desktop.fonts.enable = true;
  };
}
