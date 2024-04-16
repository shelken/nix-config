{
  # astronvim,
  astronvim-config,
  lib,
  pkgs,
  config,
  ...
}: {
  # 使用 lazygit
  imports = [
    ./packages.nix
  ];

  home.activation.installAstroNvim = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${pkgs.rsync}/bin/rsync -avz --chmod=D2755,F744 ${astronvim-config}/ ${config.xdg.configHome}/nvim/
  '';

  programs.neovim = {
    enable = true;
    defaultEditor = true;

    viAlias = true;
    vimAlias = true;

    withPython3 = true;
    withNodeJs = true;
  };
}
