{
  pkgs,
  lib,
  myvars,
  config,
  ...
}: let
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
  homeDir = config.users.users."${myvars.username}".home;
  scriptsPath = ./skhd/scripts;
in {
  # for yabai and skhd
  services.yabai = {
    enable = true;
    package = yabai;
    # https://github.com/LnL7/nix-darwin/blob/master/modules/services/yabai/default.nix
    enableScriptingAddition = false;
    extraConfig = builtins.readFile ./yabairc;
  };

  services.skhd = {
    enable = true;
    skhdConfig = ''
      #          ╭──────────────────────────────────────────────────────────╮
      #          │                        blacklist                         │
      #          ╰──────────────────────────────────────────────────────────╯

      .blacklist [
         "Screen Sharing"
         "VNC Viewer"
      ]

      #          ╭──────────────────────────────────────────────────────────╮
      #          │                       focus window                       │
      #          ╰──────────────────────────────────────────────────────────╯
      # alt - h : yabai -m window --focus west
      # alt - j : yabai -m window --focus south
      # alt - k : yabai -m window --focus north
      # alt - l : yabai -m window --focus east
      alt - left : yabai -m window --focus west
      alt - down : yabai -m window --focus south
      alt - up : yabai -m window --focus north
      alt - right : yabai -m window --focus east

      #          ╭──────────────────────────────────────────────────────────╮
      #          │                         窗口交换                         │
      #          ╰──────────────────────────────────────────────────────────╯
      ctrl + alt - r : ${scriptsPath}/cycle_counterclockwise.sh
      ctrl + alt - left : yabai -m window --swap west
      ctrl + alt - down : yabai -m window --swap south
      ctrl + alt - up : yabai -m window --swap north
      ctrl + alt - right : yabai -m window --swap east
      # 全屏
      ctrl + alt - return : yabai -m window --toggle zoom-parent
      # 切换窗口水平垂直
      ctrl + alt - l : yabai -m window --toggle split
      # 切换float
      ctrl + alt - f : yabai -m window --toggle float

      #          ╭──────────────────────────────────────────────────────────╮
      #          │                       调整窗口大小                       │
      #          ╰──────────────────────────────────────────────────────────╯
      cmd + shift - left : yabai -m window --resize left:-50:0; yabai -m window --resize right:-50:0
      cmd + shift - down : yabai -m window --resize bottom:0:50; yabai -m window --resize top:0:50
      cmd + shift - up : yabai -m window --resize top:0:-50; yabai -m window --resize bottom:0:-50
      cmd + shift - right : yabai -m window --resize right:50:0; yabai -m window --resize left:50:0

      # space

      # shift + cmd - n : yabai -m space --create
      # 在 9 个桌面之间切换
      # alt - 1 : yabai -m space --focus 1
      # alt - 2 : yabai -m space --focus 2
      # alt - 3 : yabai -m space --focus 3
      # alt - 4 : yabai -m space --focus 4
      # alt - 5 : yabai -m space --focus 5
      # alt - 6 : yabai -m space --focus 6
      # alt - 7 : yabai -m space --focus 7
      # alt - 8 : yabai -m space --focus 8
      # alt - 9 : yabai -m space --focus 9

      #          ╭──────────────────────────────────────────────────────────╮
      #          │                       switch space                       │
      #          ╰──────────────────────────────────────────────────────────╯
      alt - 1 : yabai -m query --spaces --space 1 | jq -r '.windows[0] // empty' | xargs yabai -m window --focus
      alt - 2 : yabai -m query --spaces --space 2 | jq -r '.windows[0] // empty' | xargs yabai -m window --focus
      alt - 3 : yabai -m query --spaces --space 3 | jq -r '.windows[0] // empty' | xargs yabai -m window --focus
      alt - 4 : yabai -m query --spaces --space 4 | jq -r '.windows[0] // empty' | xargs yabai -m window --focus
      alt - 5 : yabai -m query --spaces --space 5 | jq -r '.windows[0] // empty' | xargs yabai -m window --focus
      alt - 6 : yabai -m query --spaces --space 6 | jq -r '.windows[0] // empty' | xargs yabai -m window --focus
      alt - 7 : yabai -m query --spaces --space 7 | jq -r '.windows[0] // empty' | xargs yabai -m window --focus
      alt - 8 : yabai -m query --spaces --space 8 | jq -r '.windows[0] // empty' | xargs yabai -m window --focus
      alt - 9 : yabai -m query --spaces --space 9 | jq -r '.windows[0] // empty' | xargs yabai -m window --focus

      # 无关闭 sip 时使用
      # alt - 1 ; ss1
      # alt - 2 ; ss2
      # alt - 3 ; ss3
      # alt - 4 ; ss4
      # alt - 5 ; ss5
      # alt - 6 ; ss6
      # alt - 7 ; ss7
      # alt - 8 ; ss8
      # alt - 9 ; ss9

      # shift + cmd - z : yabai -m window --space next; yabai -m space --focus next
      #          ╭──────────────────────────────────────────────────────────╮
      #          │                   move window to space                   │
      #          ╰──────────────────────────────────────────────────────────╯
      shift + cmd - 1 : ${scriptsPath}/wsss.sh 1
      shift + cmd - 2 : ${scriptsPath}/wsss.sh 2
      shift + cmd - 3 : ${scriptsPath}/wsss.sh 3
      shift + cmd - 4 : ${scriptsPath}/wsss.sh 4
      shift + cmd - 5 : ${scriptsPath}/wsss.sh 5
      shift + cmd - 6 : ${scriptsPath}/wsss.sh 6
      shift + cmd - 7 : ${scriptsPath}/wsss.sh 7
      shift + cmd - 8 : ${scriptsPath}/wsss.sh 8
      shift + cmd - 9 : ${scriptsPath}/wsss.sh 9

      #          ╭──────────────────────────────────────────────────────────╮
      #          │                 交换两个space的所有窗口                  │
      #          ╰──────────────────────────────────────────────────────────╯

      ctrl + cmd + alt - 1 : ${scriptsPath}/switch_space.sh 1
      ctrl + cmd + alt - 2 : ${scriptsPath}/switch_space.sh 2
      ctrl + cmd + alt - 3 : ${scriptsPath}/switch_space.sh 3
      ctrl + cmd + alt - 4 : ${scriptsPath}/switch_space.sh 4
      ctrl + cmd + alt - 5 : ${scriptsPath}/switch_space.sh 5
      ctrl + cmd + alt - 6 : ${scriptsPath}/switch_space.sh 6
      ctrl + cmd + alt - 7 : ${scriptsPath}/switch_space.sh 7
      ctrl + cmd + alt - 8 : ${scriptsPath}/switch_space.sh 8
      ctrl + cmd + alt - 9 : ${scriptsPath}/switch_space.sh 9
    '';
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

  launchd.user.agents.yabai.serviceConfig = {
    StandardErrorPath = "${homeDir}/Library/Logs/yabai.stderr.log";
    StandardOutPath = "${homeDir}/Library/Logs/yabai.stdout.log";
  };

  launchd.user.agents.skhd.serviceConfig = {
    StandardErrorPath = "${homeDir}/Library/Logs/skhd.stderr.log";
    StandardOutPath = "${homeDir}/Library/Logs/skhd.stdout.log";
  };
}
