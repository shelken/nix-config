{
  ...
}:
{
  programs.mise = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;

    globalConfig = {
      # 让 mise 的工具路径始终排在前,避免 brew/其他 PATH 修改盖过 mise 声明的版本。
      # 解决场景:某工具同时在 brew 和 mise 声明时,brew 路径抢先导致 mise 版本锁定失效。
      settings.activate_aggressive = true;
      # 1.3.13 无 BUN_CONFIG_HTTP_IDLE_TIMEOUT，安装会在半开连接上永久挂起
      tools.bun = "1.3.14";
    };
  };

}
