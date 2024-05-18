{dotfiles, ...}: (self: _super: {
  dot-astro-nvim = dotfiles.packages."${self.system}".dot-astro-nvim;
  dot-tmux = dotfiles.packages."${self.system}".dot-tmux;
  dot-squirrel = dotfiles.packages."${self.system}".dot-squirrel;
})
