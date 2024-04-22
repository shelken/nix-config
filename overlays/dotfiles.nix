{dotfiles, ...}: let
in (_slef: super: {
  dot-astro-nvim = dotfiles.packages."${super.system}".dot-astro-nvim;
})
