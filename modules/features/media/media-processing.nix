# 音视频处理（ffmpeg-full，可选功能）
{ ... }:
{
  flake.modules.homeManager.media-processing =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        ffmpeg-full
      ];
    };
}
