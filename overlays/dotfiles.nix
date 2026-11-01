{ dotfiles, ... }:
(self: _super: {
  dot-astro-nvim = dotfiles.packages."${self.stdenv.hostPlatform.system}".dot-astro-nvim;
  dot-squirrel = dotfiles.packages."${self.stdenv.hostPlatform.system}".dot-squirrel;
})
