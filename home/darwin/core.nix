{
  myvars,
  pkgs,
  ...
}:
{
  home.homeDirectory = "/Users/${myvars.username}";
  home.packages = with pkgs; [
    gh-dash
    glab # gitlab cli

    rclone # web driver
    superfile # like yazi
    comma # use `, cowsay hello` == `nix run nixpkgs#cowsay -- hello`

    nix-search-tv # 查询各种（nixpkgs,home-manager,nur)下的包或选项
  ];
  home.shellAliases = {
    ns = "nix-search-tv print | fzf --preview 'nix-search-tv preview {}' --scheme history";
  };
}
