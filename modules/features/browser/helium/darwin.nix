# Helium 浏览器：随 gui 角色安装（与其它 GUI 应用同范围）；
# 受管扩展在 home.nix，设计说明见 README.md
{ config, ... }:
{
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.helium ];

  flake.modules.darwin.helium = {
    homebrew.casks = [ "helium-browser" ];

    system.defaults.CustomUserPreferences."net.imput.helium".NSUserKeyEquivalents = {
      "选择上一个标签" = "@←";
      "选择下一个标签" = "@→";
    };
  };
}
