# 任务/备份失败通知的 GUI 基础设施（terminal-notifier，macOS 专属）：
# task 框架与 kopia 均以绝对路径调用，此处仅保证安装进用户环境；所有 darwin 主机 → darwin.core
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.tasks ];
}
