{ config, ... }:
{
  # programs.ssh = {
  #   inherit (myvars.networking.ssh) extraConfig;
  # };
  shelken = {
    dotfiles.liveEdit = true;

    backup.backupPaths = [
      "${config.home.homeDirectory}/Code"
    ];

    dev.ai.sandbox.enable = true;
    # dev.ai.claudePreset = "cpa-codex";
    # dev.ai.claudePreset = "cpa-gemini";
    # dev.ai.claudePreset = "cpa-gemini-claude";
    # dev.ai.claudePreset = "anti-tools";
  };
}
