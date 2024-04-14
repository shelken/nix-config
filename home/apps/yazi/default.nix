{
  pkgs,
  catppuccin-yazi,
  catppuccin-bat,
  myvars,
  lib,
  ...
}: let
  bat_flavor = myvars.catppuccin_flavor;
  yazi_theme = lib.strings.toLower myvars.catppuccin_flavor;
in {
  programs.yazi = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    settings = {
      manager = {
        ratio = [2 7 7];
      };
      preview = {
        tab_size = 3;
      };
      plugin = {
        prepend_previewers = [
          {
            name = "*.md";
            run = "glow";
          }
        ];
      };
    };
    keymap = {
      manager = {
        prepend_keymap = [
          # {
          #   on = [ "f" "g"];
          #   run = "plugin fg";
          #   desc = "find file by content";
          # }
          # {
          #   on = [ "f" "f"];
          #   run = "plugin fg --args='fzf'";
          #   desc = "find file by file name";
          # }
        ];
      };
    };
  };

  home.packages = with pkgs; [
    file
    fd
    exiftool
    mediainfo
    # for markdown preview
    glow
    # for fg.yazi
    # fzf
    # ripgrep
    # bat
  ];

  xdg.configFile = {
    "yazi/theme.toml" = {
      source = catppuccin-yazi + "/themes/${yazi_theme}.toml";
    };
    "yazi/Catppuccin-${yazi_theme}.tmTheme" = {
      source = catppuccin-bat + "/themes/Catppuccin ${bat_flavor}.tmTheme";
    };
    # not good
    # "yazi/plugins/fg.yazi" = {
    #   source = pkgs.fetchFromGitHub {
    #     owner = "DreamMaoMao";
    #     repo = "fg.yazi";
    #     rev = "cc53d56";
    #     sha256 = "sha256-xUZdmDZhbUzX5Ka2xogRQJI52EL81n9ZLrcxDacgfN0=";
    #   };
    # };
    "yazi/plugins/glow.yazi" = {
      source = pkgs.fetchFromGitHub {
        owner = "Reledia";
        repo = "glow.yazi";
        rev = "cf1f1f0";
        sha256 = "sha256-U4ullcOwN6TCaZ8gXCPMk/fGbtZLe4e1Y0RhRKLZKng=";
      };
    };
    # "yazi/plugins/preview.yazi" = {
    #   source = pkgs.fetchFromGitHub {
    #     owner = "Urie96";
    #     repo = "preview.yazi";
    #     rev = "eab63ea";
    #     sha256 = "sha256-WhAZyME8IVEmGQTAIxUSMDXPf0xqqAHixYfT8lXBtIQ=";
    #   };
    # };
  };
}
