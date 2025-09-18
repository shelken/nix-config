{niri, ...}: {
  imports =
    [
      ./base
      ../base

      niri.nixosModules.niri
      ./desktop
    ]
    ++ [{programs.niri.enable = true;}];
}
