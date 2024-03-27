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
  sensible = pkgs.fetchFromGitHub {
    owner = "tmux-plugins";
    repo = "tmux-sensible";
    rev = "25cb91f42d020f675bb0a2ce3fbd3a5d96119efa";
    hash = "sha256-sw9g1Yzmv2fdZFLJSGhx1tatQ+TtjDYNZI5uny0+5Hg=";
  };
  yank = pkgs.fetchFromGitHub {
    owner = "tmux-plugins";
    repo = "tmux-yank";
    rev = "acfd36e4fcba99f8310a7dfb432111c242fe7392";
    hash = "sha256-/5HPaoOx2U2d8lZZJo5dKmemu6hKgHJYq23hxkddXpA=";
  };
  vim-tmux-navigator = pkgs.fetchFromGitHub {
    owner = "christoomey";
    repo = "vim-tmux-navigator";
    rev = "38b1d0402c4600543281dc85b3f51884205674b6";
    hash = "sha256-4WpY+t4g9mmUrRQgTmUnzpjU8WxtrJOWzIL/vY4wR3I=";
  };
  catppuccin = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "tmux";
    rev = "e80cb735bbcd264ff971fdf7e58b219b60286c81";
    hash = "sha256-l6RGtRlMsVcA8t/Qpkin8M4wX1OTFNwwpY5PSf8E+rA=";
  };
  resurrect = pkgs.fetchFromGitHub {
    owner = "tmux-plugins";
    repo = "tmux-resurrect";
    rev = "cff343cf9e81983d3da0c8562b01616f12e8d548";
    hash = "sha256-FcSjYyWjXM1B+WmiK2bqUNJYtH7sJBUsY2IjSur5TjY=";
  };
in {
  # programs.tmux = {
  #   enable = false;
  #   # plugins = with pkgs; [
  #   #   {
  #   #     plugin = tmuxPlugins.sensible;
  #   #   }
  #   #   {
  #   #     plugin = tmuxPlugins.yank;
  #   #   }
  #   #   {
  #   #     plugin = tmuxPlugins.vim-tmux-navigator;
  #   #   }
  #   #   {
  #   #     plugin = tmuxPlugins.catppuccin;
  #   #   }
  #   # ];
  # };

  home.packages = with pkgs; [
    tmux
  ];

  home.file = {
    ".tmux.conf".source = dotfiles.packages.${system}.dot-tmux + "/tmux.conf";
    ".tmux/plugins/tpm".source = tpm + "/";
    ".tmux/plugins/tmux-sensible".source = sensible + "/";
    ".tmux/plugins/tmux-yank".source = yank + "/";
    ".tmux/plugins/vim-tmux-navigator".source = vim-tmux-navigator + "/";
    ".tmux/plugins/tmux".source = catppuccin + "/";
    ".tmux/plugins/tmux-resurrect".source = resurrect + "/";
  };
}
