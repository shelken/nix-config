{lib, ...}: {
  xdg.configFile = {
    "sketchybar" = {
      source = lib.cleanSourceWith {
        src = lib.cleanSource ./sketchybar/.;
      };

      recursive = true;
    };
  };

  # home.packages = [
  #   (pkgs.callPackage ./sketchyhelper.nix {})
  # ];
}
