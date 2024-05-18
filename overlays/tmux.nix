{pkgs, ...}: let
in (_self: super: {
  tmuxPlugins.catppuccin =
    super.tmuxPlugins.catppuccin.overrideAttrs
    (_: {
      src = pkgs.fetchFromGitHub {
        owner = "catppuccin";
        repo = "tmux";
        rev = "a556353d60833367b13739e660d4057a96f2f4fe";
        hash = "sha256-i5rnMnkFGOWeRi38euttei/fVIxlrV6dQxemAM+LV0A=";
      };
      version = "2024-04-24";
    });
  tmuxPlugins.sensible =
    super.tmuxPlugins.sensible.overrideAttrs
    (_: {
      src = pkgs.fetchFromGitHub {
        owner = "tmux-plugins";
        repo = "tmux-sensible";
        rev = "25cb91f42d020f675bb0a2ce3fbd3a5d96119efa";
        hash = "sha256-sw9g1Yzmv2fdZFLJSGhx1tatQ+TtjDYNZI5uny0+5Hg=";
      };
      version = "2022-08-14";
    });
  tmuxPlugins.yank =
    super.tmuxPlugins.yank.overrideAttrs
    (_: {
      src = pkgs.fetchFromGitHub {
        owner = "tmux-plugins";
        repo = "tmux-yank";
        rev = "acfd36e4fcba99f8310a7dfb432111c242fe7392";
        hash = "sha256-/5HPaoOx2U2d8lZZJo5dKmemu6hKgHJYq23hxkddXpA=";
      };
      version = "2023-07-19";
    });
  tmuxPlugins.vim-tmux-navigator =
    super.tmuxPlugins.vim-tmux-navigator.overrideAttrs
    (_: {
      src = pkgs.fetchFromGitHub {
        owner = "christoomey";
        repo = "vim-tmux-navigator";
        rev = "38b1d0402c4600543281dc85b3f51884205674b6";
        hash = "sha256-4WpY+t4g9mmUrRQgTmUnzpjU8WxtrJOWzIL/vY4wR3I=";
      };
      version = "2023-12-23";
    });
  tmuxPlugins.resurrect =
    super.tmuxPlugins.resurrect.overrideAttrs
    (_: {
      src = pkgs.fetchFromGitHub {
        owner = "tmux-plugins";
        repo = "tmux-resurrect";
        rev = "cff343cf9e81983d3da0c8562b01616f12e8d548";
        hash = "sha256-FcSjYyWjXM1B+WmiK2bqUNJYtH7sJBUsY2IjSur5TjY=";
      };
      version = "2023-03-06";
    });
})
