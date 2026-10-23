# shelken.backup 的「备份什么」意图选项：接口声明（实现按平台提供，darwin 为 kopia）。
# kopia 实现直接加入 workstation 角色，没有 enable 开关。
# app 会被 ai（omp/pi）等功能写入，backupPaths/ignores 是主机参数。
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
}
