{
  pkgs,
  myvars,
  ...
}: {
  home.packages = with pkgs; [
    tldr
    neofetch
    just
    asciinema
    ctop

    # nix tool
    # https://github.com/nix-community/nix-melt
    # nix-melt # A TUI flake.lock viewer
    # https://github.com/utdemir/nix-tree
    nix-tree # A TUI to visualize the dependency graph of a nix derivation
    nix-prefetch-git
    nix-prefetch-github
    nix-output-monitor # nom
    nh # Yet another nix cli helper
  ];
  programs = {
    # ls 替代
    # A modern replacement for ‘ls’
    # useful in bash/zsh prompt, not in nushell.
    eza = {
      enable = true;
      git = true;
      icons = true;
    };

    # a cat(1) clone with syntax highlighting and Git integration.
    # cat 替代
    bat = {
      enable = true;
      config = {
        pager = "less -FR";
        theme = "catppuccin";
      };
      themes = {
        # https://raw.githubusercontent.com/catppuccin/bat/main/themes/Catppuccin-mocha.tmTheme
        catppuccin = {
          # src = catppuccin-bat;
          # file = "themes/Catppuccin-mocha.tmTheme";
          src = pkgs.fetchFromGitHub {
            owner = "catppuccin";
            repo = "bat"; # Bat uses sublime syntax for its themes
            rev = "b19bea35a85a32294ac4732cad5b0dc6495bed32";
            sha256 = "1y14nqhd6kxkkb053fvfa0rw72188gzmpzmnk6r3ishcq7d1dsiw";
          };
          # file = "themes/Catppuccin Mocha.tmTheme";
          file = "themes/Catppuccin ${myvars.catppuccin_flavor}.tmTheme";
        };
      };
    };

    # zoxide is a smarter cd command, inspired by z and autojump.
    # It remembers which directories you use most frequently,
    # so you can "jump" to them in just a few keystrokes.
    # zoxide works on all major shells.
    #
    #   z foo              # cd into highest ranked directory matching foo
    #   z foo bar          # cd into highest ranked directory matching foo and bar
    #   z foo /            # cd into a subdirectory starting with foo
    #
    #   z ~/foo            # z also works like a regular cd command
    #   z foo/             # cd into relative path
    #   z ..               # cd one level up
    #   z -                # cd into previous directory
    #
    #   zi foo             # cd with interactive selection (using fzf)
    #
    #   z foo<SPACE><TAB>  # show interactive completions (zoxide v0.8.0+, bash 4.4+/fish/zsh only)
    # 快速跳转
    zoxide = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      enableNushellIntegration = true;
    };
  };
}
