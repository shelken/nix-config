# agent-run：宿主上启动 Agent harness 的唯一入口。凭据经 sec-run 注入，
# agent-gh 的 gh 包装放到 PATH 最前，只作用于 harness 进程树（不放全局 PATH：那会改变用户自己用 gh 时的身份）。
# 做成可执行文件而不是别名：herdr-app 菜单、spawn-subagent 不经 shell 启动，nushell 也不认 VAR=x 前缀。
{
  flake.modules.homeManager.ai =
    { pkgs, myvars, ... }:
    let
      agentGh = import ../agent-gh/_package.nix {
        inherit pkgs;
        owner = myvars.username;
      };
    in
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "agent-run";
          text = ''
            if (($# == 0)); then
              echo "用法: agent-run <harness> [参数...]" >&2
              exit 64
            fi
            PATH="${agentGh}/bin:$PATH" exec sec-run "$@"
          '';
        })
      ];
    };
}
