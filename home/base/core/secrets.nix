{
  mylib,
  config,
  lib,
  pkgs,
  sops-nix,
  ...
}:
let
  inherit (mylib) mkBoolOpt;
  inherit (lib) mkIf;
  cfg = config.shelken.secrets;

  secretEnvMap = {
    GITHUB_TOKEN = "github/cli-token"; # 目前依赖: task
    GROQ_API_KEY = "groq/api-key";
  };

  enabledSecrets = lib.unique (lib.attrValues secretEnvMap);

  # agent profile -> 允许注入的 secret 变量白名单, 经 Nix 期展开固化进 sec-run
  profileEntries = lib.concatStringsSep "" (
    lib.mapAttrsToList (
      profile: vars: "  ${profile} \"${lib.concatStringsSep " " vars}\"\n"
    ) cfg.agentEnvMap
  );

  # 变量名 -> sops 渲染文件路径, 运行期只读文件不接触加密层
  secretPathEntries = lib.concatStringsSep "" (
    lib.mapAttrsToList (
      var: secret: "  ${var} \"${config.sops.secrets."${secret}".path}\"\n"
    ) secretEnvMap
  );
  # 脚本体在 ./sec-run.sh, 占位符在此填充
  secRun = pkgs.writeScriptBin "sec-run" (
    lib.replaceStrings
      [
        "@PROFILE_ENTRIES@"
        "@SECRET_PATH_ENTRIES@"
      ]
      [
        profileEntries
        secretPathEntries
      ]
      (lib.readFile ./sec-run.sh)
  );

in
{
  imports = [
    sops-nix.homeManagerModules.sops
  ];
  options.shelken.secrets = {
    enable = mkBoolOpt false "Whether or not use secrets";
    agentEnvMap = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      description = "agent/LLM profile 到允许注入的 secret 环境变量白名单; 变量必须在 secretEnvMap 中声明, 由各 agent 组件自行声明分管";
    };
  };
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (v: lib.hasAttr v secretEnvMap) (lib.flatten (lib.attrValues cfg.agentEnvMap));
        message = "shelken.secrets.agentEnvMap 引用了未声明变量: "
          + lib.concatStringsSep ", " (
            lib.subtractLists (lib.attrNames secretEnvMap) (lib.flatten (lib.attrValues cfg.agentEnvMap))
          );
      }
    ];

    # ─── 统一明确的 Age 解密密钥 ───
    sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    home.sessionVariables.SOPS_AGE_KEY_FILE = config.sops.age.keyFile;

    # ─── 统一凭据定义 ───
    sops.secrets = (mylib.mkSopsSecrets enabledSecrets) // {
      "wakatime/conf" = mylib.mkDefaultSecret {
        path = "${config.home.homeDirectory}/.wakatime.cfg";
      };
      "asciinema/install-id" = mylib.mkDefaultSecret {
        path = "${config.home.homeDirectory}/.config/asciinema/install-id";
      };
    };

    sops.templates."gh-hosts.yml" = {
      path = "${config.home.homeDirectory}/.config/gh/hosts.yml";
      content = ''
        github.com:
            user: ${config.home.username}
            oauth_token: ${config.sops.placeholder."github/cli-token"}
            git_protocol: ssh
      '';
      mode = "0600";
    };

    home.packages = [
      pkgs.gopass
      secRun
    ];
  };
}
