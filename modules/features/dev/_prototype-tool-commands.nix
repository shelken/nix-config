# PROTOTYPE：命令包能否封住依赖和清单，让宿主与沙箱只调用一个入口？
# 查看：nix eval --impure --json --expr 'let flake = builtins.getFlake (toString ./.); in (import ./modules/features/dev/_prototype-tool-commands.nix { inherit flake; }).summary'
# 未接入正式模块。即使手动运行生成的命令，插件与缓存也只写入临时目录，结束后删除。
{ flake }:
let
  hostSystem = builtins.currentSystem;
  guestSystem =
    if builtins.match "aarch64-.*" hostSystem != null then "aarch64-linux" else "x86_64-linux";
  pkgsFor = system: import flake.inputs.nixpkgs { inherit system; };
  hostPkgs = pkgsFor hostSystem;
  guestPkgs = pkgsFor guestSystem;
  inherit (hostPkgs) lib;

  tools = flake.homeConfigurations.mio.config.shelken.dev.tools;
  hostManifest = ../ai/omp/plugins/package.json;
  guestManifest = tools.omp.sandboxFiles.".omp/agent/plugins-package.json";
  installerSource = ../ai/omp/plugins/install.sh;

  # Bun 继续复用登记的 mise 版本；where 只查已有安装，不自动安装工具。
  mkBun =
    pkgs:
    pkgs.writeShellApplication {
      name = "bun";
      runtimeInputs = [ pkgs.mise ];
      text = ''
        bunRoot="$(mise where bun@${tools.bun.mise})"
        exec "$bunRoot/bin/bun" "$@"
      '';
    };

  mkInstaller =
    {
      pkgs,
      manifest,
      miseDataDir ? null,
    }:
    pkgs.writeShellApplication {
      name = "omp-plugins-install-prototype";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.git
        pkgs.gh
        pkgs.nodejs_24
        (mkBun pkgs)
      ];
      text = ''
        export MISE_DATA_DIR="''${MISE_DATA_DIR:-''${XDG_DATA_HOME:-$HOME/.local/share}/mise}"
        ${lib.optionalString (miseDataDir != null) ''
          export MISE_DATA_DIR=${lib.escapeShellArg miseDataDir}
        ''}

        work="$(mktemp -d -t omp-command-prototype.XXXXXX)"
        trap 'rm -rf "$work"' EXIT
        export XDG_DATA_HOME="$work/data"
        export SB_BUN_CACHE_DIR="$work/cache"
        export SB_POSTINSTALL_STRICT=1
        mkdir -p "$XDG_DATA_HOME/omp"

        ${lib.getExe pkgs.bash} ${installerSource} ${manifest}
      '';
    };

  hostInstaller = mkInstaller {
    pkgs = hostPkgs;
    manifest = hostManifest;
  };

  guestInstaller = mkInstaller {
    pkgs = guestPkgs;
    manifest = guestManifest;
    miseDataDir = "/opt/sandbox-mise";
  };

  hostActivation = ''
    if ! ${lib.getExe hostInstaller}; then
      echo "[!] 警告: OMP 插件安装失败" >&2
    fi
  '';

  sandboxSync = guestPkgs.writeShellApplication {
    name = "agent-sync-prototype";
    text = ''
      exec ${lib.getExe guestInstaller}
    '';
  };
in
{
  inherit hostInstaller guestInstaller sandboxSync;

  hostModule = { lib, ... }: {
    home.activation.installOmpPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] hostActivation;
  };

  summary = {
    question = "同一安装器源码能否生成两个平台命令，并把调用方收窄到执行命令？";
    platforms = {
      host = hostSystem;
      sandbox = guestSystem;
    };
    bun = {
      provider = "mise";
      version = tools.bun.mise;
    };
    commands = {
      host = lib.getExe hostInstaller;
      sandbox = lib.getExe sandboxSync;
    };
    callers = {
      homeManager = hostActivation;
      sandbox = "exec ${lib.getExe guestInstaller}";
    };
    safety = "未接入正式模块；运行只写临时插件和缓存；不更改工具安装来源。";
  };
}
