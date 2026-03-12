{
  lib,
  config,
  ...
}:
{
  config = lib.mkIf config.shelken.dev.ai.enable {
    programs.gemini-cli = {
      enable = true;
      commands = { };
    };

    # home.sessionVariables = {
    # };
  };
}
