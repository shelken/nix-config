{
  pkgs,
  msbConfig,
  msbHome,
  defaultConf,
  launcher,
  guestStatus,
  sandboxConfig ? null,
}:
let
  template = import ./_template.nix { inherit (pkgs) lib; };

  # 宿主 CLI：逻辑在 sb.sh，Nix 只注入路径（shellcheck 在构建期对最终产物生效）
  sbText = template ./sb.sh {
    MSB_CONFIG = msbConfig;
    MSB_HOME = msbHome;
    DEFAULT_YAML = defaultConf;
    LAUNCHER = launcher;
    GUEST_STATUS = guestStatus;
    SANDBOX_CONFIG = if sandboxConfig != null then sandboxConfig else "";
  };

  sb = pkgs.writeShellApplication {
    name = "sb";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.jq
      pkgs.yq-go
      pkgs.git
      pkgs.util-linux
      pkgs.findutils
    ];
    text = sbText;
  };

  ompSb = pkgs.writeShellScriptBin "omp-sb" ''
    set -euo pipefail
    exec ${sb}/bin/sb run omp "$@"
  '';
in
pkgs.symlinkJoin {
  name = "sb-tools";
  paths = [
    sb
    ompSb
  ];
}
