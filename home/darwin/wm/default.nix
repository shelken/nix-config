{dotfiles, pkgs, system}: 
let
  # 固定版本
  yabai = pkgs.yabai.overrideAttrs (old: rec {
    src = pkgs.fetchFromGitHub {
      owner = "donaldguy";
      repo = "yabai";
      rev = "v6.0.15";
      hash = "sha256-buX6FRIXdM5VmYpA80eESDMPf+xeMfJJj0ulyx2g94M=";
    };
  });
in
{

 # for yabai and skhd
  services.yabai = {
    enable = true;
    pkgs = yabai;
    # https://github.com/LnL7/nix-darwin/blob/master/modules/services/yabai/default.nix
    enableScriptingAddition = false;
  }; 

  services.skhd = {
    enable = true;
  };
  
  xdg.configFile = {
    "yabai" = {
      source = dotfiles.packages.${system}.dot-yabai + "/yabai";
      recursive = true;
    };
    "skhd" = {
      source = dotfiles.packages.${system}.dot-yabai + "/skhd";
      recursive = true;
    };
  };

}
