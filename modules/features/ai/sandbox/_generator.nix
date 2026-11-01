{
  pkgs,
  lib,
  config,
  nixpkgs,
  gitConfig ? null,
}:
let
  linuxSystem = "${pkgs.stdenv.hostPlatform.parsed.cpu.name}-linux";
  linuxPkgs = nixpkgs.legacyPackages.${linuxSystem};
  toolsCfg = config.shelken.dev.tools;
  hostCommandsCfg = config.shelken.dev.sandbox.hostCommands;

  # 沙箱基础环境（不登记为共享工具，理由见 ADR 0003）: bash, coreutils, curl, git, mise, bubblewrap, iproute2, iptables; plus jq, gnused, findutils, gawk
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
    tools = config.shelken.dev.miseTools;
  };

  # 发布给 guest 的配置条目来源：files 的全部条目，加上 sandboxFiles 里那些不在 files 中的
  # 沙箱专属文件（例如沙箱专用插件清单）。sandboxFiles 与 files 同名的条目是覆盖，不重复发布。
  toolTargets =
    tool:
    lib.mapAttrsToList (target: file: { inherit target file; }) tool.files
    ++ lib.mapAttrsToList (target: file: { inherit target file; }) (
      builtins.removeAttrs tool.sandboxFiles (builtins.attrNames tool.files)
    );
  allToolFiles = lib.concatMap toolTargets (builtins.attrValues toolsCfg);

  template = import ./_template.nix { inherit lib; };

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
    # 统一 guest 环境（由 generator.nix 生成，请勿手改）
    export HOME="''${HOME:-/root}"
    export XDG_DATA_HOME=/data/xdg/data
    export XDG_STATE_HOME=/data/xdg/state
    export XDG_CACHE_HOME=/data/xdg/cache
    export XDG_CONFIG_HOME=/data/xdg/config
    # guest 侧固定路径：三个 guest 脚本都 source 本文件，不再各自写一份字面量
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

  # 发布给 guest 的配置条目：目标路径 -> 内容来源
  # live-edit 主机的 home.file.source 是 out-of-store 软链（指向仓库工作区），
  # guest 上下文只挂载 store 与配置目录，因此这里在构建期解引用成自包含副本，
  # 保证 /root/.pi、/root/.omp/agent 等在上下文内可读。
  # 条目来源只有三种：sandboxFiles 的显式覆盖、{ source = ...; } 的软链目标、普通路径。
  sandboxOverrides = lib.foldl' (acc: tool: acc // tool.sandboxFiles) { } (
    builtins.attrValues toolsCfg
  );
  resolveEntry =
    item:
    if sandboxOverrides ? ${item.target} then
      sandboxOverrides.${item.target}
    else if builtins.isAttrs item.file && item.file ? source then
      item.file.source
    else
      item.file;
  configEntries = map (item: {
    inherit (item) target;
    path = resolveEntry item;
  }) allToolFiles;

  configManifest = pkgs.writeText "sandbox-config-manifest" (
    lib.concatStringsSep "\n" (map (e: "${e.target}\t${toString e.path}") configEntries) + "\n"
  );

  # 声明清单随内容发布进同一版本目录：launcher 从同一版本读清单和挂载源，二者不会错位
  declaredPaths = pkgs.writeText "declared-paths" (
    lib.concatStringsSep "\n" (map (e: e.target) configEntries) + "\n"
  );

  # 可写根清单（相对 $HOME，一行一个）：launcher 的唯一来源，与 declared-paths 同版本发布
  writableRoots = pkgs.writeText "writable-roots" (
    lib.concatMapStrings (r: "${r}\n") (
      lib.unique (lib.sort lib.lessThan config.shelken.dev.sandbox.writableRoots)
    )
  );

  # 生成沙箱发布目录配置 (挂载到 /run/sandbox-config)
  rawSandboxConfig = pkgs.linkFarm "sandbox-config-inner" (
    [
      {
        name = "mise.toml";
        path = readOnlyMiseToml;
      }
      {
        name = "guest-env.sh";
        path = guestEnvSh;
      }
      {
        name = "sync-guest.sh";
        path = syncGuestScript;
      }
      {
        name = "declared-paths";
        path = declaredPaths;
      }
      {
        name = "writable-roots";
        path = writableRoots;
      }
    ]
    ++ (map (e: {
      name = e.target;
      path = e.path;
    }) configEntries)
  );

  # 宿主侧物化脚本：把发布条目解引用成自包含副本，写入 ~/.config/sandbox/current
  # 构建期无法跟随 out-of-store 软链（Nix 构建沙箱拒绝访问），只能在宿主激活时解开；
  # 解引用后 guest 上下文读到的就是普通文件，不再依赖仓库工作区路径。
  # store 内条目仍用软链，只有 live-edit 这类仓库软链才复制。
  # 发布顺序：先写版本化目录，current.new 软链就位后同目录 rename 原子替换，
  # 消除「旧目录改名 → 新目录就位」之间的 current 空窗。
  # 运行中的上下文把声明配置按启动时的版本目录挂载，删掉旧版本会让它们读不到复制来的条目，
  # 所以旧版本保留 7 天，只清理更早的。
  publishScript = pkgs.writeShellScript "publish-sandbox-config" ''
    set -euo pipefail
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.findutils
      ]
    }:$PATH"
    cfg_root="''${SANDBOX_CONFIG_DIR:-$HOME/.config/sandbox}"
    mkdir -p "$cfg_root"
    version="v$(date +%Y%m%d%H%M%S)-$$"
    dst="$cfg_root/$version"
    tmp="''${dst}.tmp"
    rm -rf "$tmp"
    mkdir -p "$tmp"
    while IFS=$'\t' read -r target src; do
      [[ -n "$target" ]] || continue
      mkdir -p "$tmp/$(dirname "$target")"
      real="$(realpath "$src")"
      if [[ "$real" == /nix/store/* ]]; then
        ln -sfn "$real" "$tmp/$target"
      else
        cp -RL "$src" "$tmp/$target"
        chmod -R u+w "$tmp/$target"
      fi
    done < ${configManifest}
    ln -sfn ${readOnlyMiseToml} "$tmp/mise.toml"
    ln -sfn ${guestEnvSh} "$tmp/guest-env.sh"
    ln -sfn ${syncGuestScript} "$tmp/sync-guest.sh"
    ln -sfn ${declaredPaths} "$tmp/declared-paths"
    ln -sfn ${writableRoots} "$tmp/writable-roots"
    mv "$tmp" "$dst"
    # 原子切换：软链先就位为 current.new，再同目录 rename 覆盖 current（无空窗）
    ln -sfn "$version" "$cfg_root/current.new"
    mv -Tf "$cfg_root/current.new" "$cfg_root/current" 2>/dev/null || {
      # macOS 的 mv 无 -T 时回落：current 是目录的场景已不存在（本脚本只产软链），仍保留兜底
      rm -rf "$cfg_root/current.old"
      mv "$cfg_root/current" "$cfg_root/current.old" 2>/dev/null || true
      mv "$cfg_root/current.new" "$cfg_root/current"
      rm -rf "$cfg_root/current.old"
    }
    # 清理超过 7 天的旧版本（含失败残留的 .tmp），current 指向的版本与刚发布的版本始终保留
    find "$cfg_root" -mindepth 1 -maxdepth 1 -name 'v*' -mmin +$((7 * 24 * 60)) -print0 \
      | while IFS= read -r -d "" old; do
          [[ "$old" == "$dst" || "$(basename "$old")" == "$(readlink "$cfg_root/current")" ]] && continue
          rm -rf "$old"
        done
  '';

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
in
{
  inherit
    linuxPkgs
    guestBinPath
    publishScript
    guestStatus
    ;
}
