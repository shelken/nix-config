# 宿主驱动与 CLI 深模块 (SandboxHost)
# 职责：
# 1. 接收单一 SandboxManifest 规约与原生 sb.yaml 上限策略
# 2. 宿主 microsandbox 驱动配置生成
# 3. 组装并打包 sb 与 omp-sb 命令行工具
# 4. 导出宿主 sessionVariables
{
  pkgs,
  manifest,
  guest,
  policyFile,
}:
let
  msbHome = manifest.statePaths.msbHome;
  cacheDir = manifest.statePaths.cacheDir;

  msbConfig = (pkgs.formats.json { }).generate "microsandbox-config.json" {
    version = 1;
    home = msbHome;
    paths.cache = cacheDir;
    sandbox_defaults.disable_metrics_sample = true;
  };

  # 宿主 CLI：Nix 原生 writeShellApplication 打包（无宏模板替换）
  # 运行时直接读取原生的 sb.yaml
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
      export DEFAULT_MSB_HOME="${msbHome}"
      export DEFAULT_YAML="${policyFile}"
      export LAUNCHER="${guest.launcher}"
      export GUEST_STATUS="${guest.guestStatus}"
      export SB_MISE_HOST_DIR="''${SB_MISE_HOST_DIR:-${manifest.miseLayer.hostDir}}"
      export SB_MISE_GUEST_MOUNT="${manifest.miseLayer.guestMount}"
      export SB_MISE_MOUNT_MODE="${manifest.miseLayer.mountMode}"

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
  sessionVariables = {
    MSB_HOME = msbHome;
    MSB_CONFIG_PATH = "${msbConfig}";
  };
}
