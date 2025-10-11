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
}
