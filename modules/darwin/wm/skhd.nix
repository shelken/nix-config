{
  myvars,
  config,
  lib,
  mylib,
  pkgs,
  ...
}:
let
  homeDir = config.users.users."${myvars.username}".home;
  scriptsPath = ./skhd/scripts;
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.wm.skhd;
in
{
  options.shelken.wm.skhd = {
    enable = mkBoolOpt false "Whether or not to enable yabai.";
  };
  config = mkIf cfg.enable {
    system.activationScripts.skhd.text = "su - $(logname) -c '${pkgs.skhd}/bin/skhd -r'";
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
        ctrl + alt - r     : ${scriptsPath}/cycle_counterclockwise.sh
        ctrl + alt - left  : yabai -m window --swap west
        ctrl + alt - down  : yabai -m window --swap south
        ctrl + alt - up    : yabai -m window --swap north
        ctrl + alt - right : yabai -m window --swap east

        ctrl + shift - left  : yabai -m window --warp west
        ctrl + shift - down  : yabai -m window --warp south
        ctrl + shift - up    : yabai -m window --warp north
        ctrl + shift - right : yabai -m window --warp east
        # 全屏
        # options: zoom-parent, zoom-fullscreen, native-fullscreen
        ctrl + alt - return : yabai -m window --toggle zoom-fullscreen
        # 切换窗口水平垂直
        ctrl + alt - l : yabai -m window --toggle split
        # 切换float
        ctrl + alt - f : yabai -m window --toggle float

        #          ╭──────────────────────────────────────────────────────────╮
        #          │                       调整窗口大小                       │
        #          ╰──────────────────────────────────────────────────────────╯
        alt + shift - left : yabai -m window --resize left:-50:0; yabai -m window --resize right:-50:0
        alt + shift - down : yabai -m window --resize bottom:0:50; yabai -m window --resize top:0:50
        alt + shift - up : yabai -m window --resize top:0:-50; yabai -m window --resize bottom:0:-50
        alt + shift - right : yabai -m window --resize right:50:0; yabai -m window --resize left:50:0

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
        alt - 1 : ${scriptsPath}/ss.sh 1
        alt - 2 : ${scriptsPath}/ss.sh 2
        alt - 3 : ${scriptsPath}/ss.sh 3
        alt - 4 : ${scriptsPath}/ss.sh 4
        alt - 5 : ${scriptsPath}/ss.sh 5
        alt - 6 : ${scriptsPath}/ss.sh 6
        alt - 7 : ${scriptsPath}/ss.sh 7
        alt - 8 : ${scriptsPath}/ss.sh 8
        alt - 9 : ${scriptsPath}/ss.sh 9
        alt - t : ${scriptsPath}/ss.sh 2
        alt - b : ${scriptsPath}/ss.sh 1
        alt - c : ${scriptsPath}/ss.sh 3

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
        shift + cmd - 1 : yabai -m window --space 1 && ${scriptsPath}/ss.sh 1
        shift + cmd - 2 : yabai -m window --space 2 && ${scriptsPath}/ss.sh 2
        shift + cmd - 3 : yabai -m window --space 3 && ${scriptsPath}/ss.sh 3
        shift + cmd - 4 : yabai -m window --space 4 && ${scriptsPath}/ss.sh 4
        shift + cmd - 5 : yabai -m window --space 5 && ${scriptsPath}/ss.sh 5
        shift + cmd - 6 : yabai -m window --space 6 && ${scriptsPath}/ss.sh 6
        shift + cmd - 7 : yabai -m window --space 7 && ${scriptsPath}/ss.sh 7
        shift + cmd - 8 : yabai -m window --space 8 && ${scriptsPath}/ss.sh 8
        shift + cmd - 9 : yabai -m window --space 9 && ${scriptsPath}/ss.sh 9
        shift + alt - b : yabai -m window --space 1 && ${scriptsPath}/ss.sh 1
        shift + alt - t : yabai -m window --space 2 && ${scriptsPath}/ss.sh 2
        shift + alt - c : yabai -m window --space 3 && ${scriptsPath}/ss.sh 3

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

        #          ╭──────────────────────────────────────────────────────────╮
        #          │                         打开应用                         │
        #          ╰──────────────────────────────────────────────────────────╯
        # alt - k : ${scriptsPath}/kitty_quake.sh
      '';
    };

    launchd.user.agents.skhd.serviceConfig = {
      StandardErrorPath = "${homeDir}/Library/Logs/skhd.stderr.log";
      StandardOutPath = "${homeDir}/Library/Logs/skhd.stdout.log";
    };
  };
}
