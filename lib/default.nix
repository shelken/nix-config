{lib, ...}: let
  inherit (lib) mkOption types;
in {
  colmenaSystem = import ./colmenaSystem.nix;
  macosSystem = import ./macosSystem.nix;
  nixosSystem = import ./nixosSystem.nix;
  relativeToRoot = lib.path.append ../.;
  get-sops-file = file: ../. + "/sops/secrets/${file}";
  # 扫入当前目录所有除default.nix的以nix结尾的文件，以及第一层目录
  # 返回一个目录list
  scanPaths = path:
    builtins.map
    (f: (path + "/${f}"))
    (builtins.attrNames
      (lib.attrsets.filterAttrs
        (
          path: _type:
            (_type == "directory") # include directories
            || (
              (path != "default.nix") # ignore default.nix
              && (lib.strings.hasSuffix ".nix" path) # include .nix files
            )
        )
        (builtins.readDir path)));

  mkBoolOpt = default: description:
    mkOption {
      inherit default description;
      type = types.bool;
    };
}
