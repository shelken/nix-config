# PROTOTYPE：宿主上的 VM、授权、上下文编排和 CLI。
# 现有 sb.sh 保留为私有运行时后端；新结构先验证完整系统的装配和边界。
{
  pkgs,
  lib,
  spec,
  guest,
  configBundle,
}:
let
  msbConfig = (pkgs.formats.json { }).generate "sandbox-prototype-msb.json" {
    version = 1;
    home = spec.paths.vm;
    paths.cache = spec.paths.cache;
    sandbox_defaults.disable_metrics_sample = true;
  };

  msb = pkgs.writeShellApplication {
    name = "msb";
    runtimeInputs = [ pkgs.mise ];
    text = ''
      exec mise exec microsandbox@${spec.microsandboxVersion} -- msb "$@"
    '';
  };

  backend = import ../_sb.nix {
    inherit pkgs msbConfig;
    msbHome = spec.paths.vm;
    defaultConf = configBundle.policy;
    launcher = guest.contexts.enter;
    guestStatus = guest.tools.status;
  };

  contract = (pkgs.formats.json { }).generate "sandbox-prototype-contract.json" {
    inherit (spec) paths;
    config = {
      inherit (configBundle)
        root
        current
        declaredPaths
        writableRoots
        ;
      publish = lib.getExe configBundle.publish;
    };
    guest = {
      inherit (guest) system environment;
      inherit (guest) tools contexts;
    };
    operations = {
      up = [
        "vm.lock"
        "vm.ensure"
        "tools.firstSync"
      ];
      run = [
        "policy.resolve"
        "policy.requireApproval"
        "vm.ensure"
        "context.stageImports"
        "context.enter"
        "context.cleanup"
      ];
      sync = [
        "vm.ensure"
        "tools.sharedWriteLock"
        "tools.sync"
      ];
      status = [
        "vm.inspect"
        "context.count"
        "tools.status"
      ];
      trust = [
        "policy.resolve"
        "policy.storeApproval"
      ];
      down = [
        "vm.lock"
        "vm.stop"
      ];
      rm = [
        "vm.lock"
        "context.requireIdle"
        "vm.remove"
      ];
    };
    scope = "整个 sandbox 的装配原型；现有运行时后端未拆写；默认 inspect 不启动 VM。";
  };

  cli = pkgs.writeShellApplication {
    name = "sb-prototype";
    runtimeInputs = [
      pkgs.jq
      pkgs.coreutils
      msb
    ];
    text = ''
      case "''${1:-inspect}" in
        inspect)
          exec jq . ${contract}
          ;;
        publish)
          exec ${lib.getExe configBundle.publish}
          ;;
      esac

      export MSB_HOME=${lib.escapeShellArg spec.paths.vm}
      export MSB_CONFIG_PATH=${msbConfig}
      export SB_CONFIG=${configBundle.policy}
      export SB_SANDBOX_CONFIG=${lib.escapeShellArg configBundle.root}
      export SB_MISE_HOST_DIR=${lib.escapeShellArg spec.paths.mise}
      export SB_APPROVAL_DIR=${lib.escapeShellArg spec.paths.approvals}

      case "$1" in
        up|run|shell|sync)
          ${lib.getExe configBundle.publish}
          mkdir -p "$SB_MISE_HOST_DIR/data" "$SB_MISE_HOST_DIR/cache"
          ;;
      esac
      exec ${backend}/bin/sb "$@"
    '';
  };
in
{
  inherit cli contract;
  vm = {
    owns = [
      "create/start/stop/remove"
      "capability fingerprint"
      "lifecycle lock"
      "busy-context protection"
    ];
  };
  policy = {
    owns = [
      "global ceiling"
      "project paths/imports/network"
      "trust approval"
    ];
  };
}
