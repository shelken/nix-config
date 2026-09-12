{
  mylib,
  ...
}:
{
  options.shelken.neovim = {
    enable = mylib.mkBoolOpt false "是否在该主机安装 Neovim";
    minimal = mylib.mkBoolOpt false "最小化安装nvim（不带配置）";
  };

  config.shelken.internal.homeModules = [ ./home.nix ];
}
