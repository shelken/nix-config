{
  pkgs,
  spec,
  guest,
}:
let
  template = import ./_template.nix { inherit (pkgs) lib; };

  msbConfig = (pkgs.formats.json { }).generate "microsandbox-config.json" {
    version = 1;
    home = spec.paths.msbHome;
    paths.cache = spec.paths.cacheDir;
    sandbox_defaults.disable_metrics_sample = true;
  };

  # 宿主 CLI：逻辑在 sb.sh，Nix 注入所需路径与依赖（shellcheck 在构建期对最终产物生效）
  sbText = template ./sb.sh {
    MSB_CONFIG = msbConfig;
    MSB_HOME = spec.paths.msbHome;
    DEFAULT_YAML = spec.policyFile;
    LAUNCHER = guest.launcher;
    GUEST_STATUS = guest.guestStatus;
  };

  sb = pkgs.writeShellApplication {
    name = "sb";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.yq-go
      pkgs.git
      pkgs.util-linux
    ];
    text = sbText;
  };

  ompSb = pkgs.writeShellScriptBin "omp-sb" ''
    set -euo pipefail
    exec ${sb}/bin/sb run omp "$@"
  '';
in
{
  inherit
    msbConfig
    sb
    ompSb
    ;
  packages = [
    sb
    ompSb
  ];
}
