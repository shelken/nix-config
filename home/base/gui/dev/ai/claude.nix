{ lib, config, ... }:
{
  config = lib.mkIf config.shelken.dev.ai.enable {
    programs.claude-code = {
      enable = false; # use homebrew
    };
    programs.bun.enable = true;
  };
}
