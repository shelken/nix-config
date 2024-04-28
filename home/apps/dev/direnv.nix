_: {
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = true;
    config = {
      global = {
        # Hides the rather large block of text that is usually printed when entering the environment.direnv version > 2.34
        hide_env_diff = true;
      };
    };
  };
  # home.packages = [
  #   # devenv.packages."${pkgs.system}".devenv
  #   # pkgs.cachix
  # ];
}
