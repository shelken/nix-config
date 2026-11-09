# 宿主上 harness 的启动别名：在 sec-run 之前把 agent-gh 的目录放到 PATH 最前，
# omp、pi 及其子进程里的 `gh` 因此先经过包装。不放全局 PATH：那会改变用户自己用 gh 时的身份。
# 用 PATH 注入而不是 alias gh：agent 的非交互 bash 不展开 alias（trash.nix 同理）。
{ pkgs, myvars }:
name:
let
  agentGh = import ./_package.nix {
    inherit pkgs;
    owner = myvars.username;
  };
in
"PATH=${agentGh}/bin:$PATH sec-run ${name}"
