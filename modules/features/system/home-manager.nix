{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.home-manager ];

  flake.modules.homeManager.home-manager =
    {
      myvars,
      mylib,
      ...
    }:
    {
      options.shelken.dotfiles.liveEdit = mylib.mkBoolOpt false "是否使用 mkOutOfStoreSymlink 软链至本地 ~/nix-config 以支持即时编辑";

      config = {
        home = {
          inherit (myvars) username;
          stateVersion = "24.05";
        };

        programs.home-manager.enable = true;
      };
    };
}
