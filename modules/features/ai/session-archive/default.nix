# 会话归档实现：按月整体打包、压缩、age 加密已封存月份的会话文件并删除原文件，由 shelken.tasks 每天定时执行。
# 加入 workstation 角色即开启，没有 enable 开关；全部是用户态配置，
# HM 部分经同名挂接自动随 darwin.session-archive 进入。
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.session-archive ];
  # 接口选项会被 omp/pi 在任何主机上写入，所以 darwin.core 与 nixos.core 都要拿到（ADR 0004）
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.session-archive-options ];
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.session-archive-options ];

  flake.modules.homeManager.session-archive.imports = [ ./_archive ];

  flake.modules.homeManager.session-archive-options =
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
          description = "一个月结束后再过多少天才封存该月，此时该月的文件都已超过这个天数没动过";
        };
        keyFile = lib.mkOption {
          type = lib.types.str;
          default = config.sops.age.keyFile;
          defaultText = lib.literalExpression "config.sops.age.keyFile";
          description = "age 私钥文件，可含多把；加密给其中全部公钥，解密用其中任一把";
        };
      };
    };
}
