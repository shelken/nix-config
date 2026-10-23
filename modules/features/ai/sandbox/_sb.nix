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
  # 宿主 CLI：逻辑在 sb.sh，Nix 只注入路径（shellcheck 在构建期对最终产物生效）。
  # 在求值期替换源文件文本，不用 replaceVars + readFile：后者会读取依赖 Linux guest
  # 脚本的派生产物，导致求值宿主配置也要先构建 Linux 包（IFD）。
  sbText =
    builtins.replaceStrings
      [
        "@MSB_CONFIG@"
        "@MSB_HOME@"
        "@DEFAULT_YAML@"
        "@LAUNCHER@"
        "@GUEST_STATUS@"
        "@SANDBOX_CONFIG@"
      ]
      [
        "${msbConfig}"
        "${msbHome}"
        "${defaultConf}"
        "${launcher}"
        "${guestStatus}"
        (if sandboxConfig != null then "${sandboxConfig}" else "")
      ]
      (builtins.readFile ./sb.sh);

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
