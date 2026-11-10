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
    guest_gc = "${guest.gcGuestScript}";
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

  # 登记表条目声明 sandboxCommand，就得到 <名>-sb
  # herdr 在宿主侧只看得到 sb 进程；pi 要用 HERDR_AGENT 告诉它按 pi 的屏幕规则识别状态。
  # omp 没有屏幕规则，herdr 只认它自己上报的状态，这里设了也没用
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
