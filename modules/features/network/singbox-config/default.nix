{
  config,
  ...
}:
{
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.singbox-config ];
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.singbox-config ];

  flake.modules.homeManager.singbox-config =
    {
      config,
      lib,
      mylib,
      pkgs,
      ...
    }:
    let
      script = pkgs.writeShellApplication {
        name = "singbox-config";
        runtimeInputs = [ pkgs.coreutils ];
        runtimeEnv = {
          TEMPLATES_DIR = "${./templates}";
          MAIN_DOMAIN_FILE = config.sops.secrets.singbox-main-domain.path;
        };
        text = builtins.readFile ./singbox-config.sh;
      };
    in
    {
      config = lib.mkIf config.shelken.secrets.enable {
        sops.secrets.singbox-main-domain = mylib.mkDefaultSecret { key = "main-domain"; };

        programs.mise.globalConfig.tools = {
          "github:shelken/proxy" = {
            version = "latest";
            matching = "sbtools";
            minimum_release_age = "0h";
          };
        };

        home.packages = [ script ];
      };
    };
}
