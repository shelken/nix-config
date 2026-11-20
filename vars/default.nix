{ lib }:
{
  username = "shelken";
  userfullname = "Shelken Pan";
  useremail = "shelken.pxk@gmail.com";
  region = "TW";
  timeZone = "Asia/Taipei";
  catppuccin = rec {
    flavor = "macchiato";
    accent = "pink";
    displayName = "Catppuccin ${lib.toSentenceCase flavor}";
  };
  fontFamilies = {
    monospace = "Iosevka Nerd Font Mono";
    cjkMonospace = "Maple Mono NF CN";
  };
  networking = import ./networking.nix { inherit lib; };
  socketVmnet = rec {
    interface = "en0";
    socket = "/var/run/socket_vmnet.bridged.${interface}";
  };
  limaUserKeys = {
    yuuko = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIvvmHR3yD9rV5bStEdkjzLtr4pGdtJBOKzcq8DkRvA3 lima";
    sakamoto = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBeElTQ7wsNp6jg50I+QCCrbHIK4A2JxLRHyR6YA3CdH lima";
  };
  mainSshAuthorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINfTmo7KkKR3PFxUQ8mKx8lmJ3ykwaeOfkpOxsFgdaRH shelken@sakamoto"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN9sMBAahOZKZ5QXBEsu6ACfgX8TSt5EgD+E1h6mtzG2 shelken@mio"
  ];
  initialHashedPassword = "$7$CU..../....GbQ7xUejtHNrAoHWD6Qta/$T22s4jQMYtvlcRGN09nFRgWaJi5ll.rjezwyb6L.ZFD";
}
