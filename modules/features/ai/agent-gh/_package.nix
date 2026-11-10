# 构建 agent-gh：bin/gh 与真实 gh 同接口，只在三类写操作命中时换 token。
# runtimeInputs 把 pkgs.gh 放到 PATH 最前，脚本里的 `gh` 因此是真实 gh，不会递归到自己。
# 宿主传 pkgs，沙箱传 linuxPkgs。
{ pkgs, owner }:
pkgs.writeShellApplication {
  name = "gh";
  runtimeInputs = [ pkgs.gh ];
  text = ''
    AGENT_GH_OWNER=${pkgs.lib.escapeShellArg owner}
  ''
  + builtins.readFile ./agent-gh.sh;
}
