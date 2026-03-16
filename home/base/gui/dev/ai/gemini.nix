{
  lib,
  config,
  ...
}:
{
  config = lib.mkIf config.shelken.dev.ai.enable {
    programs.gemini-cli = {
      enable = false;
      commands = { };
    };

    # home.sessionVariables = {
    # };
  };
}
