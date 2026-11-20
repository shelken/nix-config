{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.macos ];

  flake.modules.darwin.macos = {
    imports = [
      ./_settings.nix
      ./_hotkeys.nix
    ];
    system.stateVersion = 5;
  };

  flake.modules.homeManager.macos.home.shellAliases.deq = "sudo xattr -r -d com.apple.quarantine";
}
