{pkgs, ...}: {
  home.packages = with pkgs; [
    waybar
    rofi
    dunst
    swaybg
    #swaylock
    swaylock-effects
    swayidle
    pamixer
    light
    brillo
    cava # 音频律动
  ];
}
