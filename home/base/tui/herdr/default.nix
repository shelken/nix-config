{ config, ... }:
let
  home = config.home.homeDirectory;
  herdrDir = "${home}/nix-config/home/base/tui/herdr";
in
{
  # 可编辑：软链到仓库源文件
  xdg.configFile."herdr/config.toml" = {
    source = config.lib.file.mkOutOfStoreSymlink "${herdrDir}/config.toml";
    force = true;
  };

  # herdr-plus Projects：整目录软链
  # 源：home/base/tui/herdr/projects/*.toml
  # 目标：~/.config/herdr/plugins/config/cloudmanic.herdr-plus/projects
  xdg.configFile."herdr/plugins/config/cloudmanic.herdr-plus/projects" = {
    source = config.lib.file.mkOutOfStoreSymlink "${herdrDir}/projects";
    force = true;
  };

  # herdr-lazy：list/lock 软链到插件 config-dir（立即生效，不靠 sessionVariables）
  # 源：home/base/tui/herdr/plugins.{list,lock}
  # 目标：~/.config/herdr/plugins/config/herdr-lazy/
  xdg.configFile."herdr/plugins/config/herdr-lazy/plugins.list" = {
    source = config.lib.file.mkOutOfStoreSymlink "${herdrDir}/plugins.list";
    force = true;
  };
  xdg.configFile."herdr/plugins/config/herdr-lazy/plugins.lock" = {
    source = config.lib.file.mkOutOfStoreSymlink "${herdrDir}/plugins.lock";
    force = true;
  };

  # herdr-lazy CLI 官方不上 PATH；包装脚本进 ~/.local/bin
  home.file.".local/bin/herdr-lazy" = {
    source = config.lib.file.mkOutOfStoreSymlink "${herdrDir}/bin/herdr-lazy";
  };
}
