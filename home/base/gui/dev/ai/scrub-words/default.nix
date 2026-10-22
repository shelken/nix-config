{
  lib,
  config,
  pkgs,
  ...
}:
let
  # 字典在 ~/.config/scrub-words/dict.tsv，不能放进 nix store（全局可读）
  scrub-words = pkgs.writeShellApplication {
    name = "scrub-words";
    runtimeInputs = [
      pkgs.python3
      pkgs.lsof
    ];
    text = ''exec python3 ${./scrub_words.py} "$@"'';
  };
in
{
  config = lib.mkIf config.shelken.dev.ai.enable {
    home.packages = [ scrub-words ];
  };
}
