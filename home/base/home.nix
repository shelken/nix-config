{
  myvars,
  mylib,
  ...
}:
{
  options.shelken.dotfiles.liveEdit = mylib.mkBoolOpt false "是否使用 mkOutOfStoreSymlink 软链至本地 ~/nix-config 以支持即时编辑";

  config = {
    # Home Manager needs a bit of information about you and the
    # paths it should manage.
    home = {
      inherit (myvars) username;
      stateVersion = "24.05";
    };

    # Let Home Manager install and manage itself.
    programs.home-manager.enable = true;
  };
}
