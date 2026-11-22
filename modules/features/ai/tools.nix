{
  config,
  lib,
  ...
}:
{
  flake.modules.homeManager.ai.shelken.dev.tools = {
    # renovate: datasource=github-releases depName=oven-sh/bun extractVersion=^bun-v(?<version>.+)$
    bun.mise = "1.4.5";
    omp = {
      sandboxCommand = "omp";
      mise = {
        name = "oh-my-pi";
        version = "latest";
        minimum_release_age = "0h";
      };
      # OMP 只在 $XDG_DATA_HOME/omp 已存在时才把插件放进 XDG 目录
      sandboxDirs = [
        "$XDG_DATA_HOME/omp"
        "$XDG_STATE_HOME/omp"
        "$XDG_CACHE_HOME/omp"
      ];
      sandboxEnv = {
        SB_OMP_MANIFEST = "$SB_CONFIG_DIR/.omp/agent/plugins-package.json";
        SB_BUN_CACHE_DIR = "$SB_MISE_CACHE_DIR/bun-cache";
      };
      postInstall = ''
        bash ${./omp/plugins/install.sh} "''${SB_OMP_MANIFEST:-${./omp/plugins/package.json}}"
      '';
    };
    mermaid-lint.mise = {
      name = "npm:@mermaid-lint/cli";
      # renovate: datasource=npm depName=@mermaid-lint/cli
      version = "0.53.1";
    };
    pi = {
      sandboxCommand = "pi";
      mise = {
        name = "npm:@earendil-works/pi-coding-agent";
        version = "latest";
        minimum_release_age = "0h";
      };
    };
  };
}
