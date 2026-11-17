# 快速查看（Quick Look）插件：Markdown 与代码高亮
{ config, ... }:
{
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.quicklook ];

  flake.modules.darwin.quicklook.homebrew.casks = [
    "qlmarkdown"
    "syntax-highlight"
  ];
}
