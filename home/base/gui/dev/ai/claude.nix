{ lib, config, ... }:
{
  config = lib.mkIf config.shelken.dev.ai.enable {
    programs.claude-code = {
      enable = true;
    };
    programs.bun.enable = true;
  };
}
