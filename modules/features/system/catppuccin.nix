{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.catppuccin ];

  flake.modules.homeManager.catppuccin =
    {
      inputs,
      myvars,
      pkgs,
      ...
    }:
    let
      portSources = builtins.fromJSON (builtins.readFile "${inputs.catppuccin}/pkgs/sources.json");
      fetchPort =
        port:
        builtins.fetchTree {
          type = "github";
          owner = "catppuccin";
          repo = port;
          inherit (portSources.${port}) rev;
          narHash = portSources.${port}.hash;
        };
    in
    {
      imports = [
        inputs.catppuccin.homeModules.catppuccin
      ];

      catppuccin = {
        enable = true;
        cache.enable = false;
        sources = inputs.catppuccin.packages.${pkgs.stdenv.hostPlatform.system}.overrideScope (
          _final: _prev: {
            whiskers = pkgs.catppuccin-whiskers;
            starship = "${fetchPort "starship"}/themes";
            palette = fetchPort "palette";
            nvim = fetchPort "nvim";
          }
        );
        autoEnable = true;
        inherit (myvars.catppuccin) accent flavor;
      };
    };
}
