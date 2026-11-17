# nushell：日常交互 shell，从 zsh 里敲 nu 进入，环境继承自 zsh；登录 shell 仍是 zsh
# 暂停使用：没有角色导入本模块。恢复时在 tui 的 imports 里加回 config.flake.modules.homeManager.nushell
{
  flake.modules.homeManager.nushell = {
    programs.nushell = {
      enable = true;
      # 从 zsh 进入时环境已就绪；要让终端直接启动 nu 时再打开
      loadSessionVariables = false;
      settings.show_banner = false;
      shellAliases.k = "kubectl";
    };

    # 外部命令补全只给 nu；zsh 仍用 oh-my-zsh 与 fzf-tab
    programs.carapace = {
      enable = true;
      enableNushellIntegration = true;
      enableZshIntegration = false;
      enableBashIntegration = false;
    };
  };
}
