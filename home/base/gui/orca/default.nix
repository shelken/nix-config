{
  config,
  ...
}:
{
  # ~/.orca/keybindings.json 是 Orca 官方唯一用户键位文件（getUserKeybindingsPath）
  # UI 改动会写穿到仓库文件；Orca 重启或 Settings→Shortcuts→Reload from Disk 生效
  home.file.".orca/keybindings.json" = {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/base/gui/orca/keybindings.json";
    force = true;
  };
}
