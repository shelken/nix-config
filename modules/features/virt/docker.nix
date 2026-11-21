{ config, ... }:
{
  flake.modules.darwin.desktop.imports = [ config.flake.modules.darwin.docker ];

  flake.modules.darwin.docker.homebrew.casks = [ "orbstack" ];

  flake.modules.nixos.docker.virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
  };

  flake.modules.homeManager.docker =
    { lib, pkgs, ... }:
    {
      programs.zsh.oh-my-zsh.plugins = [ "docker" ];
      programs.bash.profileExtra = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin ''
        source ~/.orbstack/shell/init.bash 2>/dev/null || true
      '';
      programs.zsh.profileExtra = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin ''
        source ~/.orbstack/shell/init.zsh 2>/dev/null || true
      '';
    };
}
