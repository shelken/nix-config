{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.fzf ];
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.fzf-dev ];

  flake.modules.homeManager.fzf = {
    programs.fzf = {
      enable = true;
      # HM 的 fzf zsh 集成会加载 completion.zsh，在 fzf-tab 之后覆写 ^I（Tab）绑定；只保留 zsh 模块手动加载的 key-bindings.zsh
      enableZshIntegration = false;
    };
  };

  flake.modules.homeManager.fzf-dev = {
    programs.fzf.defaultCommand = "fd --type f";
  };
}
