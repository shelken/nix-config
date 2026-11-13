# 按本地字典替换 omp/pi 会话里的脏话，手动执行；字典只在工作站上
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.scrub-words ];

  flake.modules.homeManager.scrub-words =
    { pkgs, ... }:
    let
      # 字典在 ~/.config/scrub-words/dict.txt，不能放进 nix store（全局可读）
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
