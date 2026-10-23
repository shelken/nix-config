{
  flake.modules.homeManager.ai =
    { pkgs, ... }:
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
      home.packages = [ scrub-words ];
    };
}
