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

  # Nix 到 sb 的唯一配置通道：sb 里没有内置默认路径，改路径只改 _manifest.nix 与 _mise-layer.nix
  sbConfig = (pkgs.formats.json { }).generate "sb-config.json" {
    msb_config = "${msbConfig}";
    msb_home = msbHome;
    policy_yaml = "${policyFile}";
    publish_dir = manifest.statePaths.publishDir;
    launcher = "${guest.launcher}";
    guest_status = "${guest.guestStatus}";
    guest_sync = "${guest.syncGuestScript}";
    sync_lock = "${manifest.miseLayer.hostDir}/.sync.lock";
    host_credentials = true;
    guest = {
      config_mount = manifest.guestPaths.configMount;
      contexts_dir = manifest.guestPaths.contextsDir;
      data_dir = manifest.guestPaths.dataDir;
    };
    mise = {
      host_dir = manifest.miseLayer.hostDir;
      guest_mount = manifest.miseLayer.guestMount;
    };
  };

  # msb 与 sec-run 取用户 PATH
  # -P 不把当前目录放进 sys.path：用户项目里恰好有名为 sb 的目录也不会抢走模块
  sb = pkgs.writeShellApplication {
    name = "sb";
    runtimeInputs = [
      pkgs.python3
      pkgs.yq-go
      pkgs.git
    ];
    text = ''
      export SB_CONFIG_FILE="''${SB_TEST_CONFIG:-${sbConfig}}"
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
  packages = [
    sb
    ompSb
  ];
  sessionVariables = {
    MSB_HOME = msbHome;
    MSB_CONFIG_PATH = "${msbConfig}";
  };
}
