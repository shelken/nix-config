{ lib, ... }@args:
let
  isOverlay = name: type: name != "default.nix" && (type == "directory" || lib.hasSuffix ".nix" name);
in
map (name: import (./. + "/${name}") args) (
  lib.attrNames (lib.filterAttrs isOverlay (builtins.readDir ./.))
)
