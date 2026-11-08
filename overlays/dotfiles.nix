{ inputs, ... }:
(self: _super: {
  dot-squirrel = inputs.dotfiles.packages."${self.stdenv.hostPlatform.system}".dot-squirrel;
})
