{ lib }:
{
  username = "shelken";
  userfullname = "Shelken Pan";
  useremail = "shelken.pxk@gmail.com";
  catppuccin_flavor = "Macchiato"; # Mocha
  networking = import ./networking.nix { inherit lib; };
  mainSshAuthorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINfTmo7KkKR3PFxUQ8mKx8lmJ3ykwaeOfkpOxsFgdaRH shelken@sakamoto"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN9sMBAahOZKZ5QXBEsu6ACfgX8TSt5EgD+E1h6mtzG2 shelken@mio"
  ];
  initialHashedPassword = "$7$CU..../....GbQ7xUejtHNrAoHWD6Qta/$T22s4jQMYtvlcRGN09nFRgWaJi5ll.rjezwyb6L.ZFD";
}
