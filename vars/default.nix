{lib}: {
  username = "shelken";
  userfullname = "Shelken Pan";
  useremail = "shelken.pxk@gmail.com";
  catppuccin_flavor = "Macchiato"; # Mocha
  networking = import ./networking.nix {inherit lib;};
}
