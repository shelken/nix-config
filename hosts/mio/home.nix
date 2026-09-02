{ config, ... }:
{
  # programs.ssh = {
  #   inherit (myvars.networking.ssh) extraConfig;
  # };
  shelken = {
    backup = {
      enable = true;
      backupPaths = [
        "${config.home.homeDirectory}/Code"
      ];
    };

    dev.ai.enable = true;
    # dev.ai.claudePreset = "cpa-codex";
    # dev.ai.claudePreset = "cpa-gemini";
    # dev.ai.claudePreset = "cpa-gemini-claude";
    # dev.ai.claudePreset = "anti-tools";

    dev.go.enable = true;
    dev.cloud-native.enable = true;

    secrets.enable = true;
    tools.hammerspoon.enable = false;
    # 与 darwin 侧（hosts/mio/default.nix）同名同值，两棵树互不相见需手动镜像
    tools.autoinputswitch.enable = true;
    tools.backup.enable = true;
    wm.aerospace.enable = false;
    wm.omniwm.enable = true;
  };
}
