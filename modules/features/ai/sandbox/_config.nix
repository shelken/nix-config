# 配置物化与版本发布深模块 (SandboxConfig)
# 职责：
# 接收单一 SandboxManifest 规范，生成宿主原子版本发布脚本
# （解引用外部软链、版本化目录、current.new -> current 原子替换、过期清理）
{
  pkgs,
  lib,
  manifest,
}:
let
  publishDir = manifest.statePaths.publishDir;

  # 宿主侧物化脚本构造器：把发布条目解引用成自包含副本，写入 ~/.config/sandbox/current
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
      done < ${manifest.configManifest}
      ln -sfn ${manifest.readOnlyMiseToml} "$tmp/mise.toml"
      ln -sfn ${guestEnvSh} "$tmp/guest-env.sh"
      ln -sfn ${syncGuestScript} "$tmp/sync-guest.sh"
      ln -sfn ${manifest.declaredPaths} "$tmp/declared-paths"
      ln -sfn ${manifest.writableRootsFile} "$tmp/writable-roots"
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
  inherit mkPublishScript;
}
