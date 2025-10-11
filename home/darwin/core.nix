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

    asciinema # 终端录制命令与回放

    nix-search-tv # 搜索home-manager options和 nixpkgs
  ];
}
