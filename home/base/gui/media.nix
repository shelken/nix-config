{
  pkgs,
  lib,
  config,
  mylib,
  ...
}:
# processing audio/video
{
  options.shelken.gui.media = {
    enable = mylib.mkBoolOpt false "Whether or not use.";
  };
  config = lib.mkIf config.shelken.gui.media.enable {
    home.packages = with pkgs; [
      ffmpeg-full
      yt-dlp
    ];
  };
}
