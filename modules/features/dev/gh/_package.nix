# gh：与真 gh 同接口的包装（规则见 agent-gh.sh），附带真 gh 的补全与 man 页
# 宿主传 pkgs，沙箱传 linuxPkgs；runtimeInputs 让脚本里的 gh 指向真 gh，不会递归到自己
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
