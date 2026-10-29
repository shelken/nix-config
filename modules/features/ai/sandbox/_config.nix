{
  pkgs,
  lib,
  spec,
  guest,
}:
let
  toolsCfg = spec.tools;

  # 发布给 guest 的配置条目来源：files 的全部条目，加上 sandboxFiles 里那些不在 files 中的
  # 沙箱专属文件（例如沙箱专用插件清单）。sandboxFiles 与 files 同名的条目是覆盖，不重复发布。
  toolTargets =
    tool:
    lib.mapAttrsToList (target: file: { inherit target file; }) tool.files
    ++ lib.mapAttrsToList (target: file: { inherit target file; }) (
      removeAttrs tool.sandboxFiles (builtins.attrNames tool.files)
    );
  allToolFiles = lib.concatMap toolTargets (builtins.attrValues toolsCfg);

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
    lib.concatMapStrings (r: "${r}\n") (lib.unique (lib.sort lib.lessThan spec.writableRoots))
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
    ln -sfn ${guest.readOnlyMiseToml} "$tmp/mise.toml"
    ln -sfn ${guest.guestEnvSh} "$tmp/guest-env.sh"
    ln -sfn ${guest.syncGuestScript} "$tmp/sync-guest.sh"
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
in
{
  inherit
    publishScript
    declaredPaths
    writableRoots
    configEntries
    ;
}
