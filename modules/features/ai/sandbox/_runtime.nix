{
  pkgs,
  spec,
  guest,
}:
let
  # microsandbox 驱动配置（由 Nix 编译期确定）
  msbConfig = (pkgs.formats.json { }).generate "microsandbox-config.json" {
    version = 1;
    home = spec.paths.msbHome;
    paths.cache = spec.paths.cacheDir;
    sandbox_defaults.disable_metrics_sample = true;
  };

  # 宿主 CLI：Nix 原生 writeShellApplication 打包（无模板引擎）
  # 将编译期生成的配置与 guest 派生包路径作为默认环境注入
  sb = pkgs.writeShellApplication {
    name = "sb";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.yq-go
      pkgs.git
      pkgs.util-linux
    ];
    text = ''
      export DEFAULT_MSB_CONFIG="${msbConfig}"
      export DEFAULT_MSB_HOME="${spec.paths.msbHome}"
      export DEFAULT_YAML="${spec.policyFile}"
      export LAUNCHER="${guest.launcher}"
      export GUEST_STATUS="${guest.guestStatus}"

      ${builtins.readFile ./sb.sh}
    '';
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
