{
  sources,
  ...
}:
{
  programs.zellij = {
    enable = true;
    enableBashIntegration = false; # 连接自动进入很烦，有不少问题
    enableZshIntegration = false;
    attachExistingSession = false;
  };
  catppuccin.zellij.enable = false;

  xdg.configFile = {
    "zellij/layouts".source = ./layouts;
    "zellij/plugins/zjstatus.wasm" = {
      source = sources.zjstatus.src;
      executable = true;
    };
    "zellij/config.kdl" = {
      # text = concatStrings [
      #   ''
      #     // 主题配色
      #     theme "${theme}"

      #     session_serialization true
      #     simplified_ui false
      #   ''
      #   layout_dir
      #   ''
      #     //键盘绑定
      #     keybinds {
      #       ${keybinds-config}
      #     }
      #   ''
      #   # origin_file
      #   ''
      #     plugins {
      #       zjstatus location="file:${sources.zjstatus.src}" {
      #           ${builtins.readFile ./zjstatus/catpuccin.kdl}
      #       }
      #     }
      #   ''
      # ];
      source = ./config.kdl;
    };
  };

  # 切换目录时变更tab name
  programs.zsh.initContent = ''
    zellij_tab_name_update() {
    if [[ -n $ZELLIJ ]]; then
        local current_dir=$PWD
        if [[ $current_dir == $HOME ]]; then
            current_dir="~"
        else
            # current_dir=\$\{current_dir##*/\}
            current_dir=$(basename "$current_dir")
        fi
        command nohup zellij action rename-tab $current_dir >/dev/null 2>&1
        fi
    }

    zellij_tab_name_update
    chpwd_functions+=(zellij_tab_name_update)
  '';

}
