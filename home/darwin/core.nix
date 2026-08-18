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
    # superfile # like yazi
    comma # use `, cowsay hello` == `nix run nixpkgs#cowsay -- hello`

    nix-search-tv # 查询各种（nixpkgs,home-manager,nur)下的包或选项

    # 仅暴露 timeout 一个命令，闭包约 2MB，macOS 无自带 timeout
    (runCommand "timeout" { } ''
      mkdir -p $out/bin
      ln -s ${coreutils}/bin/timeout $out/bin/timeout
    '')
  ];
  home.shellAliases = {
    ns = "nix-search-tv print | fzf --preview 'nix-search-tv preview {}' --scheme history";
  };
}
