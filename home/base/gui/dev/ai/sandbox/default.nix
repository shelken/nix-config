{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  jsonFormat = pkgs.formats.json { };

  ompConfigFiles = lib.filterAttrs (
    _: file: file.enable && lib.hasPrefix ".omp/agent/" file.target
  ) config.home.file;

  models = pkgs.runCommand "omp-sandbox-models.yml" { nativeBuildInputs = [ pkgs.yq-go ]; } ''
    yq '(.. | select(tag == "!!map") | select(has("baseUrl")) | .baseUrl) |= sub("^(https?://)(127[.]0[.]0[.]1|localhost|\\[::1\\])([:/]|$)", "''${1}host.microsandbox.internal''${3}")' ${../omp/models.yml} > "$out"
  '';

  ompConfig = pkgs.linkFarm "omp-sandbox-config" (
    lib.mapAttrsToList (_: file: {
      name = lib.removePrefix ".omp/agent/" file.target;
      path = if file.target == ".omp/agent/models.yml" then models else file.source;
    }) ompConfigFiles
  );

  linuxPkgs = inputs.nixpkgs.legacyPackages.aarch64-linux;
  machines = import ./machine.nix;
  wrap =
    name: machine:
    import ./wrapper.nix {
      inherit
        pkgs
        linuxPkgs
        name
        machine
        ;
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

    home.file.".omp/sandbox-config" = {
      source = ompConfig;
      # 挂载根保持真实目录，HM 替换子项时同一 VM 可以看见新配置
      recursive = true;
    };

    home.packages = lib.mapAttrsToList (name: machine: wrap name machine) machines;
  };
}
