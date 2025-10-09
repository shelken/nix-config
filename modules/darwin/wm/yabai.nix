{
  pkgs,
  myvars,
  config,
  pkgs-unstable,
  lib,
  mylib,
  options,
  ...
}:
let
  # 固定版本
  yabai = pkgs-unstable.yabai.overrideAttrs (_old: rec {
    version = "7.1.1";
    src =
      if pkgs.stdenv.isAarch64 then
        (pkgs.fetchzip {
          url = "https://github.com/koekeishiya/yabai/releases/download/v${version}/yabai-v${version}.tar.gz";
          hash = "sha256-LNOAT1vm6EEmcKdshMKjYWFfoRoRNbgZgjEpOTacWc8=";
        })
      else
        (pkgs.fetchFromGitHub {
          owner = "koekeishiya";
          repo = "yabai";
          rev = "v${version}";
          hash = "sha256-dznMjSaS2kkyYf7JrNf1Y++Nb5YFOmk/JQP3BBrf5Bk=";
        });
  });
  homeDir = config.users.users."${myvars.username}".home;
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.wm.yabai;
in
{
  options.shelken.wm.yabai = {
    enable = mkBoolOpt false "Whether or not to enable yabai.";
  };
  config = mkIf cfg.enable {
    # for yabai and skhd
    services.yabai = {
      enable = true;
      package = yabai;
      # https://github.com/LnL7/nix-darwin/blob/master/modules/services/yabai/default.nix
      enableScriptingAddition = false;
      extraConfig = builtins.readFile ./yabairc;
    };

    launchd.user.agents.yabai.serviceConfig = {
      StandardErrorPath = "${homeDir}/Library/Logs/yabai.stderr.log";
      StandardOutPath = "${homeDir}/Library/Logs/yabai.stdout.log";
    };
  };
}
