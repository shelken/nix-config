{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.timeout ];

  flake.modules.homeManager.timeout =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.runCommand "timeout" { } ''
          mkdir -p $out/bin
          ln -s ${pkgs.coreutils}/bin/timeout $out/bin/timeout
        '')
      ];
    };
}
