{
  lib,
  mylib,
  config,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.tools.music;
in
{
  options.shelken.tools.music = {
    enable = mkBoolOpt false "Whether or not to enable.";
  };

  config = mkIf cfg.enable {
    homebrew = {
      casks = [
        "xld" # 处理cd音频文件，flac等无损音频转化
        "musicbrainz-picard" # 音乐信息刮削
      ];
    };
  };
}
