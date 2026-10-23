{
  myvars,
  pkgs,
  ...
}:
{
  xdg.configFile."otty/config.toml" = {
    source = pkgs.replaceVars ./config.toml {
      inherit (myvars.fontFamilies) monospace;
    };
    force = true;
  };
}
