{ pkgs, owner }:
let
  wrapper = pkgs.writeShellApplication {
    name = "gh";
    runtimeInputs = [ pkgs.gh ];
    text = ''
      AGENT_GH_OWNER=${pkgs.lib.escapeShellArg owner}
    ''
    + builtins.readFile ./agent-gh.sh;
  };
in
pkgs.symlinkJoin {
  name = "gh-${pkgs.gh.version}";
  # 排在前面的 bin/gh 生效
  paths = [
    wrapper
    pkgs.gh
  ];
  meta.mainProgram = "gh";
}
