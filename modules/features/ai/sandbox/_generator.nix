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
  hostCommandsCfg = config.shelken.dev.sandbox.hostCommands or { };

  # 沙箱基础环境（不登记为共享工具，理由见 ADR 0003）: bash, coreutils, curl, git, mise, bubblewrap, iproute2, iptables; plus jq, gnused, findutils, gawk
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
    cacert
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
        ${
          if name == "just" then
            ''
              case "$1" in
                hm|sw|switch|rebuild|hm-build)
                  echo "[-] 错误: just $1 是宿主系统切换命令，沙箱内无法修改宿主系统配置"
                  exit 1
                  ;;
                *)
                  echo "[-] 错误: just 在沙箱内未安装；若需执行宿主切换命令 (just hm/sw)，沙箱内无法修改宿主系统配置: ${reason}"
                  exit 1
                  ;;
              esac
            ''
          else
            ''
              # 写 stdout：sb run 的上下文里 guest stderr 不回流，写 stderr 用户看不到原因
              echo "[-] 错误: ${name} 是宿主控制命令，沙箱内无法执行: ${reason}"
              exit 1
            ''
        }
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

  # guest 只读层 mise 配置 (由 shelken.dev.tools 中的 mise 条目生成)
  miseTools = lib.listToAttrs (
    lib.concatMap (
      name:
      let
        tool = toolsCfg.${name};
      in
      lib.optional (tool.mise != null) {
        name = if builtins.isAttrs tool.mise && tool.mise ? name then tool.mise.name else name;
        value = if builtins.isAttrs tool.mise then builtins.removeAttrs tool.mise [ "name" ] else tool.mise;
      }
    ) (builtins.attrNames toolsCfg)
  );

  readOnlyMiseToml = (pkgs.formats.toml { }).generate "sandbox-mise.toml" {
    tools = miseTools;
  };

  # 模型地址改写：loopback 在 guest 内指向 VM 自身，统一改为宿主网关 host.microsandbox.internal
  loopbackPattern = "^(https?://)(127[.]0[.]0[.]1|localhost|\\[::1\\])([:/]|$)";
  modelsOmp = pkgs.runCommand "omp-sandbox-models.yml" { nativeBuildInputs = [ pkgs.yq-go ]; } ''
    yq '(.. | select(tag == "!!map") | select(has("baseUrl")) | .baseUrl) |= sub("${loopbackPattern}", "''${1}host.microsandbox.internal''${3}")' ${../omp/models.yml} > "$out"
  '';

  # Pi 的 models.json 由 pi/default.nix 从同一份 OMP YAML 生成，需要同样的地址改写
  # jq 的 sub() 替换串只认 \(.name) 命名捕获，不是 yq 的 ${1}
  modelsPi = pkgs.runCommand "pi-sandbox-models.json" { nativeBuildInputs = [ pkgs.jq ]; } ''
    jq 'walk(if type == "object" and (.baseUrl | type) == "string"
             then .baseUrl |= sub("^(?<scheme>https?://)(?<host>127[.]0[.]0[.]1|localhost|\\[::1\\])(?<rest>[:/]|$)"; "\(.scheme)host.microsandbox.internal\(.rest)")
             else . end)' ${toolsCfg.pi.files.".pi/agent/models.json".source} > "$out"
  '';

  # pi 启动时自己安装缺失的 packages。bun 默认信任 node-pty，会跑它的安装脚本而需要 node-gyp，
  # guest 不带 C 工具链（见 README「共用 mise 安装层」）。沙箱版 settings.json 让 pi 的 bun 读一份
  # 只忽略安装脚本的配置；不用全局 bunfig，项目自己的 bun install 照常跑脚本。
  # 读仓库源文件：live-edit 主机的 home.file.source 是 out-of-store 软链，构建期跟随不了
  piBunfig = pkgs.writeText "pi-bunfig.toml" ''
    [install]
    ignoreScripts = true
  '';
  settingsPi = pkgs.runCommand "pi-sandbox-settings.json" { nativeBuildInputs = [ pkgs.jq ]; } ''
    jq '.npmCommand = ["bun", "--config=/run/sandbox-config/current/pi-bunfig.toml"]' ${../pi/settings.json} > "$out"
  '';

  allToolFiles = lib.concatMap (
    tool: lib.mapAttrsToList (target: file: { inherit target file; }) tool.files
  ) (builtins.attrValues toolsCfg);

  # 发布给 guest 的插件清单（single source：generator 决定，sync 重放时使用）
  postInstallTools = builtins.filter (name: toolsCfg.${name}.postInstall != null) (
    builtins.attrNames toolsCfg
  );

  postInstallList = pkgs.writeText "postinstall-tools" (
    lib.concatStringsSep "\n" postInstallTools + "\n"
  );

  # 生成沙箱内执行的 sync 步骤（由 sb sync 调用，只补缺，不删除现有依赖）
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
    if [[ -d /opt/sandbox-mise/data ]]; then
      # 宿主共用 mise 安装目录：所有 VM 共享同一份 installs/downloads
      export MISE_DATA_DIR=/opt/sandbox-mise/data
      export MISE_CACHE_DIR=/data/xdg/cache/mise
    else
      # 未挂载共用目录时回落到本 VM 数据盘（一次性 VM / 旧数据盘）
      export MISE_DATA_DIR=/data/xdg/data/mise
      export MISE_CACHE_DIR=/data/xdg/cache/mise
    fi
    export MISE_STATE_DIR=/data/xdg/state/mise
    export MISE_SHIMS_DIR=/data/xdg/data/mise/shims
    export MISE_SYSTEM_CONFIG_FILE=/run/sandbox-config/current/mise.toml
    export MISE_GLOBAL_CONFIG_FILE=/data/mise/config.toml
    # Bun 下载缓存共用：落到共用 mise 层 cache 下的 bun-cache
    if [[ -d /opt/sandbox-mise ]]; then
      export SB_BUN_CACHE_DIR=/opt/sandbox-mise/cache/bun-cache
      mkdir -p "$SB_BUN_CACHE_DIR" 2>/dev/null || true
    fi
    # 运行上下文禁止 mise 隐式安装；安装只允许经 sb sync 显式进行
    export MISE_AUTO_INSTALL=0
    export MISE_NOT_FOUND_AUTO_INSTALL=0
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
        jq
        mise
      ];
      text = lib.removePrefix "#!/usr/bin/env bash\n" (
        lib.replaceStrings
          [ "@guest_bin_path@" "@git_config@" "@cacert@" "@postinstall_steps@" ]
          [ guestBinPath "${gitConfig}" "${linuxPkgs.cacert}" postInstallSteps ]
          (builtins.readFile ./sync-guest.sh)
      );
    }
  }/bin/sync-guest";

  # 发布给 guest 的配置条目：目标路径 -> 内容来源
  # live-edit 主机的 home.file.source 是 out-of-store 软链（指向仓库工作区），
  # guest 上下文只挂载 store 与配置目录，因此这里在构建期解引用成自包含副本，
  # 保证 /root/.pi、/root/.omp/agent 等在上下文内可读。
  configEntries = map (item: {
    inherit (item) target;
    path =
      if item.target == ".omp/agent/models.yml" then
        modelsOmp
      else if item.target == ".pi/agent/models.json" then
        modelsPi
      else if item.target == ".pi/agent/settings.json" then
        settingsPi
      else if builtins.isAttrs item.file && item.file ? source then
        item.file.source
      else
        item.file;
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
        name = "postinstall-tools";
        path = postInstallList;
      }
      {
        name = "declared-paths";
        path = declaredPaths;
      }
      {
        name = "writable-roots";
        path = writableRoots;
      }
      {
        name = "pi-bunfig.toml";
        path = piBunfig;
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
    ln -sfn ${postInstallList} "$tmp/postinstall-tools"
    ln -sfn ${declaredPaths} "$tmp/declared-paths"
    ln -sfn ${writableRoots} "$tmp/writable-roots"
    ln -sfn ${piBunfig} "$tmp/pi-bunfig.toml"
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
        gnugrep
        jq
        mise
      ];
      text = lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile ./guest-status.sh);
    }
  }/bin/guest-status";

  # 生成沙箱发布目录配置 (支持无论是挂载到 /run/sandbox-config 还是挂载到 current 均完全兼容)
  sandboxConfig = pkgs.runCommand "sandbox-config" { } ''
    mkdir -p "$out"
    ln -s "${rawSandboxConfig}" "$out/current"
    for f in "${rawSandboxConfig}"/*; do
      base="$(basename "$f")"
      ln -s "$f" "$out/$base"
    done
  '';
in
{
  inherit
    linuxPkgs
    guestEnv
    guestBinPath
    guestEnvSh
    readOnlyMiseToml
    sandboxConfig
    publishScript
    syncGuestScript
    guestStatus
    hostCommandStubs
    ;
}
