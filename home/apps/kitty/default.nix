{myvars, ...}: let
  theme = "Catppuccin-${myvars.catppuccin_flavor}";
in {
  programs.kitty = {
    enable = true;
    theme = theme;
    shellIntegration.mode = "no-rc no-cursor"; # no-cursor make `cursor_shape` config works
    extraConfig = builtins.readFile ./kitty.conf;
  };
}
