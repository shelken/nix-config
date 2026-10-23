# 备份辅助工具（restic, restic-browser, kopia）
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.tools-backup ];

  flake.modules.darwin.tools-backup.homebrew = {
    brews = [ "restic" ];
    casks = [ "restic-browser" ];
  };

  flake.modules.homeManager.tools-backup =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        kopia
      ];
    };
}
