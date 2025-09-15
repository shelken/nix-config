{
  myvars,
  pkgs,
  ...
}: {
  home.homeDirectory = "/Users/${myvars.username}";
  home.packages = with pkgs; [
    gh
    gh-dash
    glab # gitlab cli
    nali # `traceroute 1.1.1.1 | nali` show geo location
    rclone # web driver
    superfile # like yazi
    comma # use `, cowsay hello` == `nix run nixpkgs#cowsay -- hello`
    bandwhich # 查看本地程序网络连接
    q # dns dig
  ];
}
