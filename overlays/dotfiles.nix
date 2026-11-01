{ dotfiles, ... }:
(self: _super: {
  dot-squirrel = dotfiles.packages."${self.stdenv.hostPlatform.system}".dot-squirrel;
})
