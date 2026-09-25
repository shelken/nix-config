# shelken.backup 的「备份什么」意图选项：声明放在全平台共享的 base/core，
# 任何 app 模块都可以无条件写入，无需关心平台；
# 备份实现按平台提供（darwin 为 kopia，见 home/darwin/tasks/kopia），
# 没有实现的平台上这些声明是惰性的，只表达意图。
{
  lib,
  mylib,
  ...
}:
{
  options.shelken.backup = {
    enable = mylib.mkBoolOpt false "是否开启备份";
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
