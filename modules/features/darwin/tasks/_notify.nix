{ pkgs, ... }:
{
  # 任务/备份失败通知的 GUI 基础设施（macOS 专属）
  # task 系统（modules/features/darwin/tasks/_framework.nix）与 kopia（modules/features/backup/kopia）
  # 均以绝对路径调用，此处仅保证安装进用户环境
  home.packages = [ pkgs.terminal-notifier ];
}
