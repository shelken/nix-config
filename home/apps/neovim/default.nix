{
  lib,
  mylib,
  pkgs,
  config,
  ...
}: let
  # astronvim-config = dotfiles.packages.${system}.dot-astro-nvim;
  astronvim-config = pkgs.dot-astro-nvim;
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.neovim;
in {
  options.shelken.neovim = {
    minimal = mkBoolOpt false "是否启用astroNvim";
  };

  imports = [
    ./packages.nix
  ];

  config = {
    home.activation.installAstroNvim = mkIf (!cfg.minimal) (lib.hm.dag.entryAfter ["writeBoundary"] ''
      ${pkgs.rsync}/bin/rsync -avz --delete --chmod=D2755,F744 ${astronvim-config}/ ${config.xdg.configHome}/nvim/
    '');

    programs.neovim = {
      enable = true;
      defaultEditor = true;

      viAlias = true;
      vimAlias = true;

      withPython3 = true;
      withNodeJs = true;
    };
  };
}
