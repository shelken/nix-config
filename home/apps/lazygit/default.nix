{pkgs, ...}: {
  programs.lazygit = {
    enable = true;
    settings = {
      # diff with difftastic
      git.paging.externalDiffCommand = "difft --color=always";
      # cappuccins-mocha-pink
      gui.theme = {
        activeBorderColor = ["#f5c2e7" "bold"];
        inactiveBorderColor = ["#a6adc8"];
        optionsTextColor = ["#89b4fa"];
        selectedLineBgColor = ["#313244"];
        cherryPickedCommitBgColor = ["#45475a"];
        cherryPickedCommitFgColor = ["#f5c2e7"];
        unstagedChangesColor = ["#f38ba8"];
        defaultFgColor = ["#cdd6f4"];
        searchingActiveBorderColor = ["#f9e2af"];
      };
      gui.authorColors."*" = "#b4befe";
    };
  };

  home.packages = with pkgs; [
    difftastic
  ];
}
