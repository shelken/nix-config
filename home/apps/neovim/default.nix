{
  lib,
  mylib,
  pkgs,
  config,
  pkgs-unstable,
  ...
}:
let
  # astronvim-config = dotfiles.packages.${system}.dot-astro-nvim;
  astronvim-config = pkgs.dot-astro-nvim;
  inherit (lib) mkIf;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.neovim;
in
{
  options.shelken.neovim = {
    minimal = mkBoolOpt false "是否启用astroNvim";
  };

  imports = [
    ./packages.nix
  ];

  config = {
    home.activation.installAstroNvim = mkIf (!cfg.minimal) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${pkgs.rsync}/bin/rsync -avz --delete --chmod=D2755,F744 ${astronvim-config}/ ${config.xdg.configHome}/nvim/
      ''
    );

    programs.neovim = {
      enable = true;
      package = pkgs-unstable.neovim-unwrapped;
      defaultEditor = true;

      viAlias = true;
      vimAlias = true;
    }
    // lib.optionalAttrs (!cfg.minimal) {
      # withPython3 = true;
      # withNodeJs = true;
      # extraLuaPackages = ps: [ ps.magick ]; # for nvim image plugin https://github.com/3rd/image.nvim
      # extraPackages = [ pkgs.imagemagick ]; # for nvim image plugin https://github.com/3rd/image.nvim
    };

    # Disable catppuccin to avoid conflict with my non-nix config.
    catppuccin.nvim.enable = false;
  };
}
