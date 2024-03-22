{pkgs, ...}: 
let
  # 固定版本
  yabai = pkgs.yabai.overrideAttrs (old: rec {
    version = "6.0.15";
    src = 
        if pkgs.stdenv.isAarch64
        then
          (pkgs.fetchzip {
            url = "https://github.com/koekeishiya/yabai/releases/download/v${version}/yabai-v${version}.tar.gz";
            hash = "sha256-L82N0IaC2OAZVhmu9NALencK78FeCZI2cWJyNkGH2vQ=";
          })
        else
          (pkgs.fetchFromGitHub {
            owner = "koekeishiya";
            repo = "yabai";
            rev = "v${version}";
            hash = "sha256-buX6FRIXdM5VmYpA80eESDMPf+xeMfJJj0ulyx2g94M=";
          });
  });
in
{

 # for yabai and skhd
  services.yabai = {
    enable = true;
    package = yabai;
    # https://github.com/LnL7/nix-darwin/blob/master/modules/services/yabai/default.nix
    enableScriptingAddition = false;
  }; 

  services.skhd = {
    enable = true;
  };
  
  # xdg.configFile = {
  #   "yabai" = {
  #     source = dotfiles.packages.${system}.dot-yabai + "/yabai";
  #     recursive = true;
  #   };
  #   "skhd" = {
  #     source = dotfiles.packages.${system}.dot-yabai + "/skhd";
  #     recursive = true;
  #   };
  # };

}
