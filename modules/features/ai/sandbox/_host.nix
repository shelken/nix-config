# 宿主驱动与 CLI 深模块 (SandboxHost)
# 职责：
# 1. 宿主 microsandbox 驱动配置生成
# 2. 接收原生的 sb.yaml 能力上限策略文件
# 3. 组装并打包 sb 与 omp-sb 命令行工具
# 4. 导出宿主 sessionVariables
{
  pkgs,
  msbHome,
  cacheDir ? "$HOME/.cache/microsandbox",
  policyFile,
  launcher,
  guestStatus,
}:
let
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
      export LAUNCHER="${launcher}"
      export GUEST_STATUS="${guestStatus}"

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
