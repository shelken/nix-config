{
  pkgs,
  pkgs-unstable,
  config,
  ...
}:
{
  home.sessionVariables = {
    # for go
    GOPROXY = "https://goproxy.io";
  };

  home.packages = with pkgs; [
    age
    sops
    ssh-to-age

    #-- java
    jdk17
    maven

    #-- golang
    go

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
    dive # A tool for exploring each layer in a docker image
    lazydocker # docker管理

    # misc
    protobuf

    # ts
    pnpm

    # python
    uv # python 管理（uvx）
  ];

  # for go goPath
  programs.go = {
    enable = true;
    env = {
      GOPATH = [
        "${config.home.homeDirectory}/go"
      ];
    };
  };
}
