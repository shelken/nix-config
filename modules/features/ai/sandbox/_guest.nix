# Linux 执行隔离与 Guest 运行时深模块 (SandboxGuest)
# 职责：
# 1. 接收单一 SandboxManifest，构建 Linux 交叉工具闭包 (baseTools, sharedTools, hostCommandStubs)
# 2. 统一 guest 环境与目录同源规则 (guest-env.sh)
# 3. bubblewrap 隔离执行器打包 (sb-launcher，内聚 plan、netns、registry、layout 四个窄接口子模块)
# 4. 依赖补齐 (sync-guest) 与状态探测 (guest-status) 原生封包
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
  miseLayer = manifest.miseLayer;

  # Git 全局配置（用于克隆和私有依赖凭据改写）
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
  ];

  # 共享工具 Nix 条目取仓库 nixpkgs 的 Linux 包
  sharedTools = lib.concatMap (tool: lib.optional (tool.package != null) linuxPkgs.${tool.package}) (
    builtins.attrValues toolsCfg
  );

  # 宿主控制命令桩：在沙箱内调用时报错并带声明的原因说明
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

  # 合成 guest PATH 环境
  guestEnv = linuxPkgs.buildEnv {
    name = "sandbox-guest-env";
    paths = baseTools ++ sharedTools ++ [ hostCommandStubs ];
  };

  guestBinPath = "${guestEnv}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";

  # 编译期生成的工具 postInstall 执行钩子（补充 set -euo pipefail）
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

  # 统一 guest 环境文件：sync-guest.sh、launcher 入口统一 source 本文件，单一事实来源
  guestEnvSh = pkgs.writeText "guest-env.sh" ''
    # 统一 guest 环境（由 _guest.nix 生成，请勿手改）
    export HOME="''${HOME:-/root}"
    export XDG_DATA_HOME=/data/xdg/data
    export XDG_STATE_HOME=/data/xdg/state
    export XDG_CACHE_HOME=/data/xdg/cache
    export XDG_CONFIG_HOME=/data/xdg/config
    export SB_CONFIG_DIR=/run/sandbox-config/current
    export SB_MISE_LAYER=${miseLayer.guestMount}
    export SB_OMP_MANIFEST="$SB_CONFIG_DIR/.omp/agent/plugins-package.json"
    if [[ -d "$SB_MISE_LAYER/data" ]]; then
      export MISE_DATA_DIR="$SB_MISE_LAYER/data"
      export SB_BUN_CACHE_DIR="$SB_MISE_LAYER/cache/bun-cache"
      mkdir -p "$SB_BUN_CACHE_DIR" 2>/dev/null || true
    else
      export MISE_DATA_DIR=/data/xdg/data/mise
      unset SB_BUN_CACHE_DIR
    fi
    export MISE_CACHE_DIR=/data/xdg/cache/mise
    export MISE_STATE_DIR=/data/xdg/state/mise
    export MISE_SHIMS_DIR=/data/xdg/data/mise/shims
    export MISE_SYSTEM_CONFIG_FILE="$SB_CONFIG_DIR/mise.toml"
    export MISE_GLOBAL_CONFIG_FILE=/data/mise/config.toml
    export PATH="$MISE_SHIMS_DIR:${guestBinPath}"
  '';

  # sync 脚本：Linux 版 writeShellApplication 封包
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
        export SB_GIT_CONFIG="${gitConfig}"
        export SB_POSTINSTALL_HOOK="${postInstallHook}"
        ${lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile ./sync-guest.sh)}
      '';
    }
  }/bin/sync-guest";

  # guest 状态探测脚本：Linux 版 writeShellApplication 封包
  guestStatus = "${
    linuxPkgs.writeShellApplication {
      name = "guest-status";
      runtimeInputs = with linuxPkgs; [
        bashInteractive
        coreutils
        jq
        mise
      ];
      text = lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile ./guest-status.sh);
    }
  }/bin/guest-status";

  # launcher 隔离执行器：自包含打包 plan、netns、registry、layout 模块
  launcherTools = with linuxPkgs; [
    bashInteractive
    coreutils
    util-linux
    bubblewrap
    iproute2
    jq
    iptables
    gawk
  ];

  launcher = "${
    linuxPkgs.writeShellApplication {
      name = "sb-launcher";
      runtimeInputs = launcherTools;
      text = ''
        export SB_GUEST_BIN_PATH="${guestBinPath}"
        export SB_GIT_CONFIG="${gitConfig}"
        export SB_MISE_LAYER="${miseLayer.guestMount}"
        export SB_MISE_BWRAP_BIND="${miseLayer.bwrapBind}"
        ${lib.concatStringsSep "\n        " (
          lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") miseLayer.contextEnv
        )}

        # 内嵌 4 个内部窄接口模块 (plan, netns, registry, layout)
        ${builtins.readFile ./guest/plan.sh}
        ${builtins.readFile ./guest/netns.sh}
        ${builtins.readFile ./guest/registry.sh}
        ${builtins.readFile ./guest/layout.sh}

        # 内嵌主调度逻辑
        ${linuxPkgs.lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile ./launcher.sh)}
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
