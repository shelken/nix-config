# timeout：macOS 没有自带，只从 coreutils 暴露这一个命令（闭包约 2MB）
# 所有 darwin 主机 → darwin.core
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
