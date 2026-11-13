# worktrunk（wt）：git worktree 管理，工作区统一放在 ~/Code/worktrees
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
          worktrunk = "0.81";
        };
        home.file = {
          ".config/worktrunk/config.toml".source = tomlFormat.generate "worktrunk-config.toml" {
            worktree-path = "~/Code/worktrees/{{ repo }}/{{ branch | sanitize }}";
          };
        };
        programs.zsh.initContent = ''
          # worktrunk (wt) shell integration
          if command -v wt >/dev/null 2>&1; then
            eval "$(wt config shell init zsh)"
          fi
        '';
      };
    };
}
