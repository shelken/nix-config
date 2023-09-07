{
  pkgs,
  astronvim,
  ...
}: {
  xdg.configFile = {
    # astronvim's config
    "nvim".source = astronvim;

    # my cusotom astronvim config, astronvim will load it after base config
    # https://github.com/AstroNvim/AstroNvim/blob/v3.32.0/lua/astronvim/bootstrap.lua#L15-L16
    "astronvim/lua/user".source = ./astronvim_user;
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;

    viAlias = false;
    vimAlias = true;
  };

  home.packages = with pkgs; [
    gcc # 插件需要
  ];
}
