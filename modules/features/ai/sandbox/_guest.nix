{
  pkgs,
  lib,
  nixpkgs,
  manifest,
}:
let
  linuxSystem = "${pkgs.stdenv.hostPlatform.parsed.cpu.name}-linux";
  linuxPkgs = nixpkgs.legacyPackages.${linuxSystem};
  toolsCfg = manifest.tools;
  hostCommandsCfg = manifest.hostCommands;
  inherit (manifest) miseLayer guestPaths;
  stripShebang = file: lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile file);

  gitConfig = (pkgs.formats.gitIni { }).generate "sandbox-git-config" {
    user = manifest.gitUser;
    credential."https://github.com".helper = "!gh auth git-credential";
    url."https://github.com/".insteadOf = "git@github.com:";
  };

  # 沙箱基础环境（不登记为共享工具，理由见 ADR 0003）
  baseTools = with linuxPkgs; [
    bashInteractive
    coreutils
    curl
    git
    mise
    bubblewrap
    iproute2
    iptables
    jq
    gnused
    findutils
    gawk
    openssh
    dig
  ];

  sharedTools = lib.concatMap (tool: lib.optional (tool.package != null) linuxPkgs.${tool.package}) (
    builtins.attrValues toolsCfg
  );

  hostCommandStubs = pkgs.runCommand "sandbox-host-command-stubs" { } (
    ''
      mkdir -p "$out/bin"
    ''
    + lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: reason: ''
        cat <<'EOF' > "$out/bin/${name}"
        #!/bin/sh
        # 写 stdout：sb run 的上下文里 guest stderr 不回流，写 stderr 用户看不到原因
        echo "[-] 错误: ${name} 是宿主控制命令，沙箱内无法执行: ${reason}"
        exit 1
        EOF
        chmod +x "$out/bin/${name}"
      '') hostCommandsCfg
    )
  );

  guestEnv = linuxPkgs.buildEnv {
    name = "sandbox-guest-env";
    paths = baseTools ++ sharedTools ++ [ hostCommandStubs ];
  };

  guestBinPath = "${guestEnv}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";

  postInstallHook = linuxPkgs.writeShellScript "sandbox-guest-postinstall-hook" (
    ''
      set -euo pipefail
    ''
    + lib.concatStringsSep "\n" (
      lib.concatMap (
        name:
        let
          tool = toolsCfg.${name};
        in
        lib.optional (tool.postInstall != null) ''
          echo "[sb sync] 执行 ${name} postInstall..."
          ${tool.postInstall}
        ''
      ) (builtins.attrNames toolsCfg)
    )
  );

  toolEnvExports = lib.concatMapStrings (
    tool:
    lib.concatMapStrings (name: "export ${name}=\"${tool.sandboxEnv.${name}}\"\n") (
      builtins.attrNames tool.sandboxEnv
    )
  ) (builtins.attrValues toolsCfg);
  guestDirs = lib.concatMapStringsSep " " (d: "\"${d}\"") (
    [
      "$SB_DATA_DIR/mise"
      "$XDG_DATA_HOME/mise"
      "$XDG_CACHE_HOME/mise"
      "$XDG_CONFIG_HOME/mise"
      "$MISE_SHIMS_DIR"
    ]
    ++ lib.concatMap (tool: tool.sandboxDirs) (builtins.attrValues toolsCfg)
  );

  # guest 里固定路径与环境的唯一出处，sync-guest、launcher、guest-status 都加载它
  guestEnvSh = pkgs.writeText "guest-env.sh" ''
    export HOME="''${HOME:-/root}"
    export SB_CONFIG_MOUNT=${guestPaths.configMount}
    export SB_CONFIG_DIR=${guestPaths.configDir}
    export SB_CONTEXTS_DIR=${guestPaths.contextsDir}
    export SB_DATA_DIR=${guestPaths.dataDir}
    export SB_MISE_LAYER=${miseLayer.guestMount}
    export XDG_DATA_HOME="$SB_DATA_DIR/xdg/data"
    export XDG_STATE_HOME="$SB_DATA_DIR/xdg/state"
    export XDG_CACHE_HOME="$SB_DATA_DIR/xdg/cache"
    export XDG_CONFIG_HOME="$SB_DATA_DIR/xdg/config"
    export SB_MISE_DATA_DIR="$SB_MISE_LAYER/${miseLayer.dataSub}"
    export SB_MISE_CACHE_DIR="$SB_MISE_LAYER/${miseLayer.cacheSub}"
    export MISE_DATA_DIR="$SB_MISE_DATA_DIR"
    export MISE_CACHE_DIR="$XDG_CACHE_HOME/mise"
    export MISE_STATE_DIR="$XDG_STATE_HOME/mise"
    export MISE_SHIMS_DIR="$XDG_DATA_HOME/mise/shims"
    export MISE_SYSTEM_CONFIG_FILE="$SB_CONFIG_DIR/mise.toml"
    export MISE_GLOBAL_CONFIG_FILE="$SB_DATA_DIR/mise/config.toml"
    export GIT_CONFIG_GLOBAL=${gitConfig}
    export GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt
    ${toolEnvExports}export PATH="$MISE_SHIMS_DIR:${guestBinPath}"
    mkdir -p ${guestDirs}
  '';

  # 各 guest 脚本先在这里定位发布目录再加载 guest-env.sh：它在发布目录里，引导路径只能由 Nix 注入
  guestEnvPrelude = ''
    export SB_CONFIG_DIR=${guestPaths.configDir}
    # shellcheck source=/dev/null
    source "$SB_CONFIG_DIR/guest-env.sh"
  '';

  syncGuestScript = "${
    linuxPkgs.writeShellApplication {
      name = "sync-guest";
      runtimeInputs = with linuxPkgs; [
        bashInteractive
        coreutils
        git
        mise
      ];
      text = ''
        ${guestEnvPrelude}
        export SB_POSTINSTALL_HOOK="${postInstallHook}"
        ${stripShebang ./sync-guest.sh}
      '';
    }
  }/bin/sync-guest";

  guestStatus = "${
    linuxPkgs.writeShellApplication {
      name = "guest-status";
      runtimeInputs = with linuxPkgs; [
        bashInteractive
        coreutils
        jq
        mise
      ];
      text = ''
        ${guestEnvPrelude}
        ${stripShebang ./guest-status.sh}
      '';
    }
  }/bin/guest-status";

  launcher = "${
    linuxPkgs.writeShellApplication {
      name = "sb-launcher";
      text = ''
        ${guestEnvPrelude}
        ${lib.concatStringsSep "\n        " (
          lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") miseLayer.contextEnv
        )}

        ${builtins.readFile ./guest/plan.sh}
        ${builtins.readFile ./guest/netns.sh}
        ${builtins.readFile ./guest/registry.sh}
        ${builtins.readFile ./guest/layout.sh}

        ${stripShebang ./launcher.sh}
      '';
    }
  }/bin/sb-launcher";
in
{
  inherit
    guestEnvSh
    syncGuestScript
    guestStatus
    launcher
    ;
}
