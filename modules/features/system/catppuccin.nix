# catppuccin：主题基座
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
      # starship 主题与 palette.json 在求值期被读取，用 whiskers 构建的 port 会触发 IFD：
      # 远端装机（nixos-anywhere）时，目标平台的构建产物没有签名，拷回求值机被拒（#335）。
      # 改为求值期直接取上游源码，rev/hash 沿用 catppuccin 自己锁定的版本。
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
        # The default `enable` value for all available programs.
        enable = true;
        cache.enable = false;
        # issue: https://github.com/catppuccin/nix/issues/927#issuecomment-4456677608
        sources = inputs.catppuccin.packages.${pkgs.stdenv.hostPlatform.system}.overrideScope (
          _final: _prev: {
            whiskers = pkgs.catppuccin-whiskers;
            starship = "${fetchPort "starship"}/themes";
            palette = fetchPort "palette";
          }
        );
        autoEnable = true;
        inherit (myvars.catppuccin) accent flavor;
      };
    };
}
