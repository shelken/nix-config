{pkgs, ...}: {
  home.sessionVariables = {
    # for go
    GOPROXY = "https://goproxy.io";
  };

  home.packages = with pkgs; [
    age
    sops

    #-- java
    jdk17
    maven

    #-- golang
    go

    #-- rust
    cargo
    rustc
    rust-analyzer
    rustfmt

    #-- deploy
    ansible
    sshpass

    #-- container
    dive # A tool for exploring each layer in a docker image

    # misc
    protobuf
  ];
}
