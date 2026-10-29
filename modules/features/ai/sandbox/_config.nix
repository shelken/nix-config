# 配置物化与版本发布深模块 (SandboxConfig)
# 职责：
# 1. 静态前置约束断言（可写根合法性、不嵌套、工具路径覆盖）
# 2. 声明配置收集与 live-edit 外部软链解引用
# 3. 宿主原子版本发布（版本化目录、current.new -> current 原子替换、过期清理）
{
  pkgs,
  lib,
  tools,
  miseTools,
  writableRoots,
  publishDir ? "$HOME/.config/sandbox",
}:
let
  # 可写根与声明配置的一致性断言
  under = root: p: p == root || lib.hasPrefix "${root}/" p;
  targets = lib.concatMap (
    tool: builtins.attrNames tool.files ++ builtins.attrNames tool.sandboxFiles
  ) (builtins.attrValues tools);

  assertions = [
    {
      assertion = lib.all (
        r:
        r != ""
        && !(lib.hasPrefix "/" r)
        && !(lib.hasSuffix "/" r)
        && !(lib.hasPrefix ".config/" r)
        && !(builtins.elem ".." (lib.splitString "/" r))
      ) writableRoots;
      message = "shelken.dev.sandbox.writableRoots: 每项必须是 $HOME 下的相对路径，不能为空、以 / 结尾、含 .. 或落在 .config/ 下：${builtins.toJSON writableRoots}";
    }
    {
      assertion = lib.all (a: lib.all (b: a == b || !(under a b)) writableRoots) writableRoots;
      message = "shelken.dev.sandbox.writableRoots: 根之间不能嵌套：${builtins.toJSON writableRoots}";
    }
    {
      assertion = lib.all (t: lib.hasPrefix ".config/" t || lib.any (r: under r t) writableRoots) targets;
      message = "shelken.dev.tools.*.files 的目标必须落在某个 writableRoots 下或位于 .config/ 下，否则沙箱无处挂载：${
        builtins.toJSON (
          builtins.filter (t: !(lib.hasPrefix ".config/" t || lib.any (r: under r t) writableRoots)) targets
        )
      }";
    }
  ];

  # guest 只读层 mise 配置：规格与宿主 programs.mise 共用同一张表
  readOnlyMiseToml = (pkgs.formats.toml { }).generate "sandbox-mise.toml" {
    tools = miseTools;
  };

  # 发布给 guest 的配置条目来源：files 的全部条目，加上 sandboxFiles 里那些不在 files 中的
  # 沙箱专属文件。sandboxFiles 与 files 同名的条目是覆盖，不重复发布。
  toolTargets =
    tool:
    lib.mapAttrsToList (target: file: { inherit target file; }) tool.files
    ++ lib.mapAttrsToList (target: file: { inherit target file; }) (
      removeAttrs tool.sandboxFiles (builtins.attrNames tool.files)
    );
  allToolFiles = lib.concatMap toolTargets (builtins.attrValues tools);

  sandboxOverrides = lib.foldl' (acc: tool: acc // tool.sandboxFiles) { } (builtins.attrValues tools);
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
  writableRootsFile = pkgs.writeText "writable-roots" (
    lib.concatMapStrings (r: "${r}\n") (lib.unique (lib.sort lib.lessThan writableRoots))
  );

  # 宿主侧物化脚本构造器：把发布条目解引用成自包含副本，写入 ~/.config/sandbox/current
  # 接收 guest 侧生成的静态环境脚本与 sync 脚本路径
  mkPublishScript =
    { guestEnvSh, syncGuestScript }:
    pkgs.writeShellScript "publish-sandbox-config" ''
      set -euo pipefail
      export PATH="${
        lib.makeBinPath [
          pkgs.coreutils
          pkgs.findutils
        ]
      }:$PATH"
      cfg_root="''${SANDBOX_CONFIG_DIR:-${publishDir}}"
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
      ln -sfn ${writableRootsFile} "$tmp/writable-roots"
      mv "$tmp" "$dst"
      # 原子切换：软链先就位为 current.new，再同目录 rename 覆盖 current（无空窗）
      ln -sfn "$version" "$cfg_root/current.new"
      mv -Tf "$cfg_root/current.new" "$cfg_root/current" 2>/dev/null || {
        # macOS 的 mv 无 -T 时回落
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
in
{
  inherit
    assertions
    readOnlyMiseToml
    declaredPaths
    writableRootsFile
    mkPublishScript
    ;
}
