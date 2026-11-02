# 宿主驱动与 CLI 深模块 (SandboxHost)
# 职责：
# 1. 接收单一 SandboxManifest 规约与原生 sb.yaml 上限策略
# 2. 生成 microsandbox 驱动配置与 sb-config.json（Nix 到 sb 的唯一配置通道）
# 3. 打包 py/sb 为 sb 与 omp-sb 命令行工具
# 4. 导出宿主 sessionVariables
{
  pkgs,
  lib,
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

  # sb 读取的全部 Nix 侧事实。sb 里没有内置默认路径，改路径只改这里与 _mise-layer.nix
  sbConfig = (pkgs.formats.json { }).generate "sb-config.json" {
    msb_config = "${msbConfig}";
    msb_home = msbHome;
    policy_yaml = "${policyFile}";
    launcher = "${guest.launcher}";
    guest_status = "${guest.guestStatus}";
    mise = {
      host_dir = manifest.miseLayer.hostDir;
      guest_mount = manifest.miseLayer.guestMount;
      mount_mode = manifest.miseLayer.mountMode;
    };
  };

  # 宿主 CLI：py/sb 包，只依赖标准库；YAML 经 yq 转 JSON，版本控制经 git。msb 与 sec-run 取用户 PATH
  # -P 不把当前目录放进 sys.path：用户项目里恰好有名为 sb 的目录也不会抢走模块
  sb = pkgs.writeShellApplication {
    name = "sb";
    runtimeInputs = [
      pkgs.python3
      pkgs.yq-go
      pkgs.git
    ];
    text = ''
      export SB_CONFIG_FILE=${sbConfig}
      export PYTHONPATH=${
        lib.fileset.toSource {
          root = ./py;
          fileset = ./py/sb;
        }
      }
      exec python3 -P -m sb "$@"
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
