# btop：系统监视器（home/base/core/btop.nix 迁入）
{
  flake.modules.homeManager.btop = {
    # replacement of htop/nmon
    programs.btop = {
      enable = true;
      settings = {
        theme_background = false; # make btop transparent
      };
    };
  };
}
