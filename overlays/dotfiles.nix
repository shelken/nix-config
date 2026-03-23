{ dotfiles, ... }:
(self: _super: {
  dot-astro-nvim = dotfiles.packages."${self.stdenv.hostPlatform.system}".dot-astro-nvim;
  dot-tmux = dotfiles.packages."${self.stdenv.hostPlatform.system}".dot-tmux;
  dot-squirrel = dotfiles.packages."${self.stdenv.hostPlatform.system}".dot-squirrel;
})
