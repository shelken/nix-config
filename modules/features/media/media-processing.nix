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
