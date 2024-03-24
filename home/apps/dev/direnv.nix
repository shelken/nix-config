{pkgs, ...}: {
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = true;
  };
  home.packages = [
    # devenv.packages."${pkgs.system}".devenv
    # pkgs.cachix
  ];
}
