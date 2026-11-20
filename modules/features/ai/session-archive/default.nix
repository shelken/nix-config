{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.session-archive ];
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
