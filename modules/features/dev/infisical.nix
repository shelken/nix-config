{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.infisical ];

  flake.modules.homeManager.infisical =
    {
      ...
    }:
    let
      projectId = "a3590f21-2f07-4972-b74d-62cf80154383";
    in
    {
      # renovate: datasource=github-releases depName=Infisical/cli
      programs.mise.globalConfig.tools.infisical = "0.43";

      home.sessionVariables = {
        INFISICAL_PROJECT_ID = projectId;
        INFISICAL_DISABLE_UPDATE_CHECK = "true";
      };
    };
}
