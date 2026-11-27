{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.tools-base ];

  flake.modules.homeManager.tools-base.shelken.dev.tools = {
    rg.package = "ripgrep";
    fd = { };
    jq = { };
    node.package = "nodejs";
    python3 = { };
    uv = { };

    # renovate: datasource=github-releases depName=j178/prek
    prek.mise = "0.5.12";
  };
}
