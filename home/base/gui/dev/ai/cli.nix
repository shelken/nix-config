{ lib, config, ... }:
{
  config = lib.mkIf config.shelken.dev.ai.enable {
    programs.bun.enable = true;
    programs.opencode = {
      enable = false; # use homebrew
    };
  };
}
