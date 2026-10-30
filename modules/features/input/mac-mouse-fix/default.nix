# Mac Mouse Fix：鼠标平滑滚动、按键手势映射与免激活
{ config, ... }:
{
  # 挂载到 gui 角色（所有含图形界面的 darwin 桌面机）
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.mac-mouse-fix ];

  # 系统侧：安装 Cask
  flake.modules.darwin.mac-mouse-fix.homebrew.casks = [ "mac-mouse-fix" ];

  # 用户态：配置合并与免激活命令
  flake.modules.homeManager.mac-mouse-fix =
    { lib, pkgs, ... }:
    let
      activateMmf = pkgs.writeShellScriptBin "activate-mmf" ''
        if [ "''${1:-}" = "undo" ] || [ "''${1:-}" = "reset" ]; then
          defaults delete com.nuebling.mac-mouse-fix AppleLocale 2>/dev/null || true
          defaults delete com.nuebling.mac-mouse-fix.helper AppleLocale 2>/dev/null || true
        else
          defaults write com.nuebling.mac-mouse-fix AppleLocale -string "zh_CN"
          defaults write com.nuebling.mac-mouse-fix.helper AppleLocale -string "zh_CN"
        fi
        killall "Mac Mouse Fix" 2>/dev/null || true
        killall "Mac Mouse Fix Helper" 2>/dev/null || true
        open -a "Mac Mouse Fix" 2>/dev/null || true
      '';
    in
    {
      home.packages = [
        activateMmf
        (pkgs.writeShellScriptBin "reset-mmf-trial" ''
          exec activate-mmf "$@"
        '')
      ];

      home.activation.macMouseFixSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        file="$HOME/Library/Application Support/com.nuebling.mac-mouse-fix/config.plist"
        if [ -f "$file" ]; then
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              key: value:
              "run /usr/bin/plutil -replace ${key} -json ${lib.escapeShellArg (builtins.toJSON value)} \"$file\""
            ) (import ./_settings.nix)
          )}
        fi
      '';
    };
}
