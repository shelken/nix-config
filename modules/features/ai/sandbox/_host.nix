{
  pkgs,
  lib,
  manifest,
  guest,
  policyFile,
  hostSecretFiles,
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
    host_secret_files = hostSecretFiles;
    # APFS 本地快照，普通用户即可执行；系统会在磁盘紧张时清除，只用于撤销近期误删
    snapshot_cmd = lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
      "/usr/bin/tmutil"
      "localsnapshot"
    ];
    guest = {
      config_mount = manifest.guestPaths.configMount;
      contexts_dir = manifest.guestPaths.contextsDir;
      data_dir = manifest.guestPaths.dataDir;
    };
    mise = {
      host_dir = manifest.miseLayer.hostDir;
      guest_mount = manifest.miseLayer.guestMount;
      url_replacements_file = manifest.miseUrlReplacementsFile;
    };
  };

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

  harnessSbs = lib.concatMap (
    tool:
    lib.optional (tool.sandboxCommand != null) (
      pkgs.writeShellScriptBin "${tool.sandboxCommand}-sb" ''
        set -euo pipefail
        ${lib.optionalString (tool.sandboxCommand == "pi") "export HERDR_AGENT=pi"}
        exec ${sb}/bin/sb run ${tool.sandboxCommand} "$@"
      ''
    )
  ) (builtins.attrValues manifest.tools);
in
{
  packages = [ sb ] ++ harnessSbs;
  sessionVariables = {
    MSB_HOME = msbHome;
    MSB_CONFIG_PATH = "${msbConfig}";
  };
}
