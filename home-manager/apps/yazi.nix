{pkgs, ...}: {

  imports = [
    ./zoxide.nix
  ];

  programs.yazi = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  home.packages = with pkgs; [
    file
    jq
    fd
    fzf
    unar
    #zoxide
  ];

}
