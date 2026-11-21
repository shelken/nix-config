{
  flake.modules.homeManager.nushell = {
    programs.nushell = {
      enable = true;
      loadSessionVariables = false;
      settings.show_banner = false;
    };
  };
}
