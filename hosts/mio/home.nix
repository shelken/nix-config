{ config, ... }:
{
  # programs.ssh = {
  #   inherit (myvars.networking.ssh) extraConfig;
  # };
  shelken = {
    dotfiles.liveEdit = true;

    backup = {
      enable = true;
      backupPaths = [
        "${config.home.homeDirectory}/Code"
      ];
    };

    dev.ai.enable = true;
    dev.ai.sandbox.enable = true;
    # dev.ai.claudePreset = "cpa-codex";
    # dev.ai.claudePreset = "cpa-gemini";
    # dev.ai.claudePreset = "cpa-gemini-claude";
    # dev.ai.claudePreset = "anti-tools";

    dev.go.enable = true;
    dev.cloud-native.enable = true;

    infisical.enable = true; # 试用 Infisical CLI, 与 sops/sec-run 并存
    tools.hammerspoon.enable = false;
    tools.backup.enable = true;
    wm.aerospace.enable = false;
    wm.omniwm.enable = true;
  };
}
