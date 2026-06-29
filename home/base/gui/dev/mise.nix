{
  ...
}:
{
  programs.mise = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;

    # 让 mise 的工具路径始终排在前,避免 brew/其他 PATH 修改盖过 mise 声明的版本。
    # 解决场景:某工具同时在 brew 和 mise 声明时,brew 路径抢先导致 mise 版本锁定失效。
    globalConfig.settings.activate_aggressive = true;
  };

}
