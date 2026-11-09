# shelken.sessionArchive 的接口选项：声明在 core，让 omp/pi 等功能在任何主机上都能写入 app，
# 归档实现只在 workstation 角色提供（见 default.nix）。
{
  config,
  lib,
  ...
}:
{
  options.shelken.sessionArchive = {
    app = lib.mkOption {
      type = with lib.types; attrsOf (listOf str);
      default = { };
      description = "各 app 模块声明的会话目录，key 为 app 名；目录下的冷文件会被归档";
      example = {
        pi = [ "\${config.home.homeDirectory}/.pi/agent/sessions" ];
      };
    };
    afterDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = "mtime 超过多少天的文件算冷文件";
    };
    keyFile = lib.mkOption {
      type = lib.types.str;
      default = config.sops.age.keyFile;
      defaultText = lib.literalExpression "config.sops.age.keyFile";
      description = "age 私钥文件，可含多把；加密给其中全部公钥，解密用其中任一把";
    };
  };
}
