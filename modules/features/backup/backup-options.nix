# 备份接口选项：backupPaths / app / ignores；实现按平台提供，darwin 为 kopia/
# 「会被其他功能写入的接口选项必须声明在 core」（ADR 0004）；
# NixOS 主机上也有写入 shelken.backup.app 的可能，darwin.core 与 nixos.core 都要拿到
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.backup-options ];
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.backup-options ];

  flake.modules.homeManager.backup-options =
    {
      lib,
      ...
    }:
    {
      options.shelken.backup = {
        app = lib.mkOption {
          type = with lib.types; attrsOf (listOf str);
          default = { };
          description = "各 app 模块自己声明的备份路径，key 为 app 名";
          example = {
            pi = [ "\${config.home.homeDirectory}/.config/pi" ];
          };
        };
        backupPaths = lib.mkOption {
          type = with lib.types; listOf str;
          default = [ ];
          description = "要备份的路径列表（文件或目录）";
          example = [
            ''"''${config.home.homeDirectory}/Documents"''
            ''"''${config.home.homeDirectory}/Pictures"''
            ''"''${config.home.homeDirectory}/important-file.txt"''
          ];
        };
        ignores = lib.mkOption {
          type = with lib.types; listOf str;
          default = [ ];
          description = "用户自定义的忽略模式列表，自动与当前机器 user@host 默认策略合并去重（不影响其他 target）";
          example = [
            "node_modules"
            "dist"
            ".cache"
          ];
        };
      };
    };
}
