{
  pkgs,
  dotfiles,
  system,
  ...
}: let
  tpm = pkgs.fetchFromGitHub {
    owner = "tmux-plugins";
    repo = "tpm";
    rev = "99469c4a9b1ccf77fade25842dc7bafbc8ce9946";
    hash = "sha256-hW8mfwB8F9ZkTQ72WQp/1fy8KL1IIYMZBtZYIwZdMQc=";
  };
in {
  programs.tmux = {
    enable = true;
    plugins = with pkgs; [
      {
        plugin = tmuxPlugins.sensible;
      }
      {
        plugin = tmuxPlugins.yank;
      }
      {
        plugin = tmuxPlugins.vim-tmux-navigator;
      }
      {
        plugin = tmuxPlugins.catppuccin;
      }
    ];
  };

  xdg.configFile = {
    ".tmux.conf".source = dotfiles.packages.${system}.dot-tmux + "/tmux.conf";
    ".tmux/plugins/tpm".source = tpm + "/";
  };
}
