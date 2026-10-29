{ pkgs, ... }:
{
  # 任务/备份失败通知的 GUI 基础设施（macOS 专属）
  # task 系统（lib/tasks.nix 生成的通知）与 kopia（modules/features/backup/_kopia/service.nix）
  # 均以绝对路径调用，此处仅保证安装进用户环境
  home.packages = [ pkgs.terminal-notifier ];
}
