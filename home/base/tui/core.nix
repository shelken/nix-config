{
  pkgs,
  pkgs-unstable,
  ...
}:
{
  home.packages = with pkgs; [
    age
    sops
    ssh-to-age

    #-- rust
    pkgs-unstable.cargo
    pkgs-unstable.rustc
    pkgs-unstable.rust-analyzer
    pkgs-unstable.rustfmt

    #-- deploy
    ansible
    ansible-lint
    sshpass

    #-- container

    # misc
    protobuf
    #oha  #压测工具: https://github.com/hatoo/oha
    asciinema # 终端录制命令与回放

    # ts
    pnpm

    # python
    uv # python 管理（uvx）

    # nix
    nh # Yet another nix cli helper

    # net
    q # dns dig
    nali # `traceroute 1.1.1.1 | nali` show geo location
  ];

  home.shellAliases = {
    record = "asciinema rec --overwrite -i 1 --rows 28 --cols 140";
  };
}
