# 会话归档实现：按月整体打包、压缩、age 加密已封存月份的会话文件并删除原文件，由 shelken.tasks 每天定时执行。
# 加入 workstation 角色即开启，没有 enable 开关；全部是用户态配置，
# HM 部分经同名挂接自动随 darwin.session-archive 进入。
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.session-archive ];

  flake.modules.homeManager.session-archive.imports = [ ./_archive ];
}
