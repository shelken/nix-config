{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.nix-tools ];

  flake.modules.homeManager.nix-tools =
    { lib, pkgs, ... }:
    {
      home.packages =
        with pkgs;
        [
          nix-melt
          nix-tree
          nix-output-monitor
        ]
        ++ lib.optionals stdenv.hostPlatform.isDarwin [
          comma
          nix-search-tv
        ];
      home.shellAliases = lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        ns = "nix-search-tv print | fzf --preview 'nix-search-tv preview {}' --scheme history";
      };
    };
}
