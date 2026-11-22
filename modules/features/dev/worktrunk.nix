{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.worktrunk ];

  flake.modules.homeManager.worktrunk =
    {
      config,
      pkgs,
      ...
    }:
    let
      tomlFormat = pkgs.formats.toml { };
    in
    {
      config = {
        programs.mise.globalConfig.tools = {
          # renovate: datasource=github-releases depName=max-sixty/worktrunk
          worktrunk = "0.83";
        };
        home.file = {
          ".config/worktrunk/config.toml".source = tomlFormat.generate "worktrunk-config.toml" {
            worktree-path = "~/Code/worktrees/{{ repo }}/{{ branch | sanitize }}";
          };
        };
        programs.zsh.initContent = ''
          if command -v wt >/dev/null 2>&1; then
            eval "$(wt config shell init zsh)"
          fi
        '';

        # wt 由 mise 安装、nu 没有 eval：每次启动在 env.nu 里生成脚本，放进随后加载的 vendor autoload 目录
        programs.nushell.extraEnv = ''
          let wt_init = ($nu.data-dir | path join vendor autoload worktrunk.nu)
          if (which wt | is-not-empty) {
            mkdir ($wt_init | path dirname)
            ^wt config shell init nu | save --force $wt_init
          } else if ($wt_init | path exists) {
            rm $wt_init
          }
        '';
      };
    };
}
