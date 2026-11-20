{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.proxy ];
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.proxy-client ];

  flake.modules.homeManager.proxy.home.file.".proxychains/proxychains.conf".source =
    ./proxychains.conf;

  flake.modules.darwin.proxy-client.homebrew.casks = [
    "sfm"
  ];
}
