{pkgs, ...}: {
  home.packages = with pkgs; [
    age
    sops

    #-- java
    # jdk17
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

    # misc
    protobuf
  ];
}
