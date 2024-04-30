{dotfiles, ...}: (slef: _super: {
  dot-astro-nvim = dotfiles.packages."${slef.system}".dot-astro-nvim;
  dot-tmux = dotfiles.packages."${slef.system}".dot-tmux;
})
