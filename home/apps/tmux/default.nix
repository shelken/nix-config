{
  pkgs,
  dotfiles,
  system,
  lib,
  myvars,
  ...
}: let
  inherit (lib) concatStrings;
  baseConf = builtins.readFile (dotfiles.packages.${system}.dot-tmux + "/tmux.conf");
  theme = lib.strings.toLower myvars.catppuccin_flavor;
in {
  programs.tmux = {
    enable = true;
    keyMode = "vi"; # emacs or vi
    clock24 = true;
    mouse = true;
    newSession = true; # Automatically spawn a session if trying to attach and none are running.
    terminal = "tmux-256color";
    disableConfirmationPrompt = true; # Disable confirmation prompt before killing a pane or window
    baseIndex = 1;
    plugins = with pkgs; [
      {
        plugin = tmuxPlugins.sensible;
      }
      {
        plugin = tmuxPlugins.yank;
      }
      {
        plugin = tmuxPlugins.resurrect;
      }
      {
        plugin = tmuxPlugins.vim-tmux-navigator;
      }
      {
        plugin = tmuxPlugins.catppuccin;
        extraConfig = ''
          set -g @catppuccin_flavour ${theme}
        '';
      }
    ];
    extraConfig = concatStrings [
      baseConf
      ''
        # my nix extraConfig for tmux

      ''
    ];
  };
}
