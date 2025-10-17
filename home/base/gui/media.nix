{
  pkgs,
  ...
}:
# processing audio/video
{
  home.packages = with pkgs; [
    ffmpeg-full

    yt-dlp
  ];
}
