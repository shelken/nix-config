# 发布脚本：把声明配置解引用成自包含的版本化目录，再原子切换 current。
{
  pkgs,
  lib,
  manifest,
  guest,
}:
let
  publishDir = manifest.statePaths.publishDir;
  devMiseTools = manifest.miseTools;
  devWritableRoots = manifest.writableRoots;

  # 工具本体装在共用层；这份声明只读发布给 guest
  miseToml = (pkgs.formats.toml { }).generate "sandbox-mise.toml" {
    tools = devMiseTools;
  };

  configEntries = manifest.declaredEntries;

  configManifest = pkgs.writeText "sandbox-config-manifest" (
    lib.concatStringsSep "\n" (map (e: "${e.target}\t${toString e.path}") configEntries) + "\n"
  );

  declaredPaths = pkgs.writeText "declared-paths" (
    lib.concatStringsSep "\n" (map (e: e.target) configEntries) + "\n"
  );

  writableRootsFile = pkgs.writeText "writable-roots" (
    lib.concatMapStrings (r: "${r}\n") (lib.unique (lib.sort lib.lessThan devWritableRoots))
  );

  publishScript =
    let
      inherit (guest) guestEnvSh syncGuestScript;
    in
    pkgs.writeShellScript "publish-sandbox-config" ''
      set -euo pipefail
      export PATH="${
        lib.makeBinPath [
          pkgs.coreutils
          pkgs.findutils
        ]
      }:$PATH"
      cfg_root="''${1:-${publishDir}}"
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
      ln -sfn ${miseToml} "$tmp/mise.toml"
      ln -sfn ${guestEnvSh} "$tmp/guest-env.sh"
      ln -sfn ${syncGuestScript} "$tmp/sync-guest.sh"
      ln -sfn ${declaredPaths} "$tmp/declared-paths"
      ln -sfn ${writableRootsFile} "$tmp/writable-roots"
      mv "$tmp" "$dst"
      # current 不能有空窗：先就位 current.new，再 rename 覆盖
      ln -sfn "$version" "$cfg_root/current.new"
      mv -Tf "$cfg_root/current.new" "$cfg_root/current"
      find "$cfg_root" -mindepth 1 -maxdepth 1 -name 'v*' -mmin +$((7 * 24 * 60)) -print0 \
        | while IFS= read -r -d "" old; do
            [[ "$old" == "$dst" || "$(basename "$old")" == "$(readlink "$cfg_root/current")" ]] && continue
            rm -rf "$old"
          done
    '';
in
{
  inherit publishScript;
}
