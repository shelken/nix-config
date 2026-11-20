{
  flake.modules.homeManager.nushell = {
    programs.nushell = {
      enable = true;
      loadSessionVariables = false;
      settings.show_banner = false;
      shellAliases.k = "kubectl";
    };

    programs.carapace = {
      enable = true;
      enableNushellIntegration = true;
      enableZshIntegration = false;
      enableBashIntegration = false;
    };
  };
}
