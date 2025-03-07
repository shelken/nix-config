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
    enableZshIntegration = true;
    enableBashIntegration = true;
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
    "yazi/yazi.toml" = {
      source = ./yazi.toml;
    };
    "yazi/keymap.toml" = {
      source = ./keymap.toml;
    };
    "yazi/init.lua" = {
      source = ./init.lua;
    };
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
        rev = "c76bf4fb";
        hash = "sha256-DPud1Mfagl2z490f5L69ZPnZmVCa0ROXtFeDbEegBBU=";
      };
    };
    # "yazi/plugins/mime.yazi" = {
    #   source = pkgs.fetchFromGitHub {
    #     owner = "DreamMaoMao";
    #     repo = "mime.yazi";
    #     rev = "8e866b9c";
    #     hash = "sha256-RGev5ecsBrzJHlooWw24FWZMjpwUshPMGRUc4UIh5mg=";
    #   };
    # };
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
