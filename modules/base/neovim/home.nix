{
  config,
  lib,
  osConfig,
  pkgs,
  pkgs-unstable,
  ...
}:
let
  # astronvim-config = dotfiles.packages.${system}.dot-astro-nvim;
  astronvim-config = pkgs.dot-astro-nvim;
  cfg = osConfig.shelken.neovim;
in
{
  imports = [
    ./packages.nix
  ];

  config = lib.mkIf cfg.enable {
    home.activation.installAstroNvim = lib.mkIf (!cfg.minimal) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${pkgs.rsync}/bin/rsync -avz --delete --chmod=D2755,F744 ${astronvim-config}/ ${config.xdg.configHome}/nvim/
      ''
    );

    programs.neovim = {
      enable = true;
      package = pkgs-unstable.neovim-unwrapped;
      defaultEditor = true;
      withRuby = true;
      withPython3 = true;

      # 变更原因：AstroNvim 通过 rsync 管理 ~/.config/nvim/init.lua，HM 只能通过 wrapper 加载 provider 配置，避免双重管理同一文件。
      sideloadInitLua = true;

      viAlias = true;
      vimAlias = true;

      # extraLuaPackages = ps: [ ps.magick ]; # for nvim image plugin https://github.com/3rd/image.nvim
      # extraPackages = [ pkgs.imagemagick ]; # for nvim image plugin https://github.com/3rd/image.nvim
    };

    # Disable catppuccin to avoid conflict with my non-nix config.
    catppuccin.nvim.enable = lib.mkIf (!cfg.minimal) false;
  };
}
