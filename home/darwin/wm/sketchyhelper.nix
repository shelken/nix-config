{
  stdenv,
  lib,
  ...
}:
stdenv.mkDerivation (_finalAttrs: {
  pname = "sketchyhelper";
  version = "unstable-2024-03-26";

  src = lib.cleanSource ./sketchybar/helpers/.;

  meta = {
    description = "A helper program for direct communication with SketchyBar";
    homepage = "https://github.com/shelken/my-nix-flake";
    license = lib.licenses.gpl3;
    mainProgram = "sketchyhelper";
    platforms = lib.platforms.darwin;
  };
})
