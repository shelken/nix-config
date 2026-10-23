# IINA: 现代多媒体播放器与 ffmpeg
{ config, ... }:
{
  flake.modules.darwin.desktop.imports = [ config.flake.modules.darwin.iina ];

  flake.modules.darwin.iina = {
    homebrew = {
      brews = [ "ffmpeg" ];
      casks = [ "iina" ];
    };

    system.defaults.CustomUserPreferences."com.colliderli.iina" = {
      arrowBtnAction = 1; # 左右箭头按钮的功能 1 切换上下集 2 快进快退
    };
  };
}
