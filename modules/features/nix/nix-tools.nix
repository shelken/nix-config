# nix 周边工具：nix-melt、nix-tree、nix-output-monitor；comma、nix-search-tv 只在 darwin 上装
{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.nix-tools ];

  flake.modules.homeManager.nix-tools =
    { lib, pkgs, ... }:
    {
      home.packages =
        with pkgs;
        [
          nix-melt # flake.lock 的 TUI 查看器
          nix-tree # derivation 依赖图的 TUI
          nix-output-monitor # nom
        ]
        ++ lib.optionals stdenv.hostPlatform.isDarwin [
          comma # `, cowsay hello` 等于 `nix run nixpkgs#cowsay -- hello`
          nix-search-tv # 查 nixpkgs、home-manager、NUR 的包与选项
        ];
      home.shellAliases = lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        ns = "nix-search-tv print | fzf --preview 'nix-search-tv preview {}' --scheme history";
      };
    };
}
