# herdr：任务编排器配置（home/base/tui/herdr 迁入）
{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.herdr ];

  flake.modules.homeManager.herdr =
    {
      config,
      mylib,
      ...
    }:
    {
      # 可编辑：软链到仓库源文件
      xdg.configFile."herdr/config.toml" = mylib.mkConfigFile config ./config.toml;

      # herdr-plus Projects：整目录软链
      # 源：modules/features/dev/herdr/projects/*.toml
      # 目标：~/.config/herdr/plugins/config/cloudmanic.herdr-plus/projects
      xdg.configFile."herdr/plugins/config/cloudmanic.herdr-plus/projects" =
        mylib.mkConfigFile config ./projects;

      # herdr-lazy：list/lock 软链到插件 config-dir（立即生效，不靠 sessionVariables）
      # 源：modules/features/dev/herdr/plugins.{list,lock}
      # 目标：~/.config/herdr/plugins/config/herdr-lazy/
      xdg.configFile."herdr/plugins/config/herdr-lazy/plugins.list" =
        mylib.mkConfigFile config ./plugins.list;
      xdg.configFile."herdr/plugins/config/herdr-lazy/plugins.lock" =
        mylib.mkConfigFile config ./plugins.lock;

      # herdr-lazy CLI 官方不上 PATH；包装脚本进 ~/.local/bin
      home.file.".local/bin/herdr-lazy" = mylib.mkConfigFile config ./bin/herdr-lazy;
    };
}
