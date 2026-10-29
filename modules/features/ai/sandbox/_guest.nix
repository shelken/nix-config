{
  pkgs,
  lib,
  nixpkgs,
  spec,
  gitConfig,
}:
let
  linuxSystem = "${pkgs.stdenv.hostPlatform.parsed.cpu.name}-linux";
  linuxPkgs = nixpkgs.legacyPackages.${linuxSystem};
  toolsCfg = spec.tools;
  hostCommandsCfg = spec.hostCommands;

  template = import ./_template.nix { inherit (linuxPkgs) lib; };

  # 沙箱基础环境（不登记为共享工具，理由见 ADR 0003）:
  # bash, coreutils, curl, git, mise, bubblewrap, iproute2, iptables, jq, gnused, findutils, gawk, openssh
  # 不带 C 工具链：沙箱里排除了依赖 node-pty 的 simple-plannotator，没有需要现场编译的原生依赖。
  # 没有预编译产物的原生依赖在沙箱里装不上，这是刻意的取舍（引入 gcc 会让闭包多约 333 MiB）。
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

  # guest 只读层 mise 配置：规格与宿主 programs.mise 共用同一张表
  readOnlyMiseToml = (pkgs.formats.toml { }).generate "sandbox-mise.toml" {
    tools = spec.miseTools;
  };

  # 生成沙箱内执行的 sync 步骤（由 sb sync 调用）
  postInstallSteps = lib.concatStringsSep "\n" (
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
  );

  # 统一 guest 环境文件：sync-guest.sh、launcher、wrapper 入口统一 source 本文件，单一事实来源
  # 运行时模式：安装目录指向宿主共用层（只读使用），cache 与 state/shims 留在本 VM 可写层
  # sb sync 场景由 sync-guest.sh 在 source 后覆盖为可写共用 cache
  guestEnvSh = pkgs.writeText "guest-env.sh" ''
    # 统一 guest 环境（由 guest.nix 生成，请勿手改）
    export HOME="''${HOME:-/root}"
    export XDG_DATA_HOME=/data/xdg/data
    export XDG_STATE_HOME=/data/xdg/state
    export XDG_CACHE_HOME=/data/xdg/cache
    export XDG_CONFIG_HOME=/data/xdg/config
    # guest 侧固定路径：所有 guest 脚本都 source 本文件，不再各自写一份字面量
    export SB_CONFIG_DIR=/run/sandbox-config/current
    export SB_MISE_LAYER=/opt/sandbox-mise
    # 沙箱版 OMP 插件清单（已按 sandboxExclude 过滤）；宿主没有这个变量，postInstall 回落到仓库原件
    export SB_OMP_MANIFEST="$SB_CONFIG_DIR/.omp/agent/plugins-package.json"
    # 共用层是否可用只判断一次，MISE_DATA_DIR 与 SB_BUN_CACHE_DIR 必须同源，
    # 否则会出现安装目录在数据盘、下载缓存在共用层的错配
    if [[ -d "$SB_MISE_LAYER/data" ]]; then
      export MISE_DATA_DIR="$SB_MISE_LAYER/data"
      export SB_BUN_CACHE_DIR="$SB_MISE_LAYER/cache/bun-cache"
      mkdir -p "$SB_BUN_CACHE_DIR" 2>/dev/null || true
    else
      # 未挂载共用目录时回落到本 VM 数据盘（一次性 VM / 旧数据盘）
      export MISE_DATA_DIR=/data/xdg/data/mise
      unset SB_BUN_CACHE_DIR
    fi
    export MISE_CACHE_DIR=/data/xdg/cache/mise
    export MISE_STATE_DIR=/data/xdg/state/mise
    export MISE_SHIMS_DIR=/data/xdg/data/mise/shims
    export MISE_SYSTEM_CONFIG_FILE="$SB_CONFIG_DIR/mise.toml"
    export MISE_GLOBAL_CONFIG_FILE=/data/mise/config.toml
    # 运行上下文禁止 mise 隐式安装；安装只允许经 sb sync 显式进行
    export MISE_AUTO_INSTALL=0
    export PATH="$MISE_SHIMS_DIR:${guestBinPath}"
  '';

  # sync 脚本正文在独立文件 sync-guest.sh；Nix 只做占位符替换（不引入 IFD）。
  # guest 侧用 Linux 版 writeShellApplication 打包，构建期同样过 shellcheck；
  # 源文件自带 shebang 供直接阅读/检查，打包时去掉（writeShellApplication 写自己的 shebang）。
  syncGuestScript = "${
    linuxPkgs.writeShellApplication {
      name = "sync-guest";
      runtimeInputs = with linuxPkgs; [
        bashInteractive
        coreutils
        git
        mise
      ];
      text = lib.removePrefix "#!/usr/bin/env bash\n" (
        template ./sync-guest.sh {
          git_config = gitConfig;
          postinstall_steps = postInstallSteps;
        }
      );
    }
  }/bin/sync-guest";

  # guest 侧状态查询脚本（sb status 调用）：正文在 guest-status.sh，
  # 只用 PATH 里的 mise/jq，不注入任何 Nix 路径。
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

  # launcher 隔离执行器：正文在 launcher.sh，Linux 版 writeShellApplication 打包。
  # 在 guest 内以 root 建网络命名空间与 bubblewrap 视图，运行命令，退出清理。
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
      text = linuxPkgs.lib.removePrefix "#!/usr/bin/env bash\n" (
        template ./launcher.sh {
          guest_bin_path = guestBinPath;
          git_config = gitConfig;
        }
      );
    }
  }/bin/sb-launcher";
in
{
  inherit
    linuxPkgs
    guestBinPath
    readOnlyMiseToml
    guestEnvSh
    syncGuestScript
    guestStatus
    launcher
    ;
}
