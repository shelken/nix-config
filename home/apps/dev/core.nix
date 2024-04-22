{pkgs, ...}: {
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
  programs.java = {
    enable = true;
    package = pkgs.jdk17;
  };
}
