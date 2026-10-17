{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  jsonFormat = pkgs.formats.json { };

  linuxPkgs = pkgs.pkgsCross.aarch64-multiplatform;
  machines = import ./machine.nix;
  wrap = name: machine: import ./wrapper.nix {
    inherit pkgs linuxPkgs name machine;
    inherit (inputs.llm-agents.packages.aarch64-linux) omp;
  };
in
{
  config = lib.mkIf config.shelken.dev.ai.enable {
    home.file.".microsandbox/config.json".source = jsonFormat.generate "microsandbox-config.json" {
      version = 1;
      home = "${config.home.homeDirectory}/Data/sandboxes/msb";
      paths = {
        cache = "${config.home.homeDirectory}/.cache/microsandbox";
      };
    };

    home.packages = lib.mapAttrsToList (name: machine: wrap name machine) machines;
  };
}
