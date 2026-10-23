# 音视频处理（ffmpeg-full，可选）
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
