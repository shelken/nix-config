{myvars, ...}: let
  theme = "Catppuccin-${myvars.catppuccin_flavor}";
in {
  programs.kitty = {
    enable = true;
    theme = theme;
    extraConfig = builtins.readFile ./kitty.conf;
  };
}
