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

    dev.ai.sandbox.enable = true;
    # dev.ai.claudePreset = "cpa-codex";
    # dev.ai.claudePreset = "cpa-gemini";
    # dev.ai.claudePreset = "cpa-gemini-claude";
    # dev.ai.claudePreset = "anti-tools";

    dev.go.enable = true;
    dev.cloud-native.enable = true;

    infisical.enable = true; # 试用 Infisical CLI, 与 sops/sec-run 并存
    tools.backup.enable = true;
  };
}
