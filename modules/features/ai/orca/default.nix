# Orca 键位管理：配置并入 AI 功能（orca 应用本体由 ai 的 homebrew cask 安装，仅 workstation 有）
{ config, ... }:
{
  # HM 配置与应用本体同角色：workstation 专属；其他主机没有 orca，无此文件属预期
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.orca ];

  flake.modules.homeManager.orca =
    { config, mylib, ... }:
    {
      # ~/.orca/keybindings.json 是 Orca 官方唯一用户键位文件（getUserKeybindingsPath）
      # UI 改动会写穿到仓库文件；Orca 重启或 Settings→Shortcuts→Reload from Disk 生效
      home.file.".orca/keybindings.json" = mylib.mkConfigFile config ./keybindings.json;
    };
}
