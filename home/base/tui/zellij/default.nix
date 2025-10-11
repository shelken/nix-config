{
  pkgs,
  ...
}:
let
  zjstatus = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "zjstatus";
    version = "v0.21.1";

    src = builtins.fetchurl {
      url = "https://github.com/dj95/zjstatus/releases/download/${version}/zjstatus.wasm";
      sha256 = "sha256:dc1982a208c27f66871e69811458fbb1abdb15e28662fddb136b575d6564ae1a";
    };
    phases = [ "installPhase" ];

    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/zjstatus
      chmod +x $out/bin/zjstatus
    '';
  };
in
{
  programs.zellij = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    attachExistingSession = false;
  };
  catppuccin.zellij.enable = false;

  xdg.configFile = {
    "zellij/layouts".source = ./layouts;
    "zellij/plugins/zjstatus.wasm".source = "${zjstatus}/bin/zjstatus";
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
      #       zjstatus location="file:${zjstatus}/bin/zjstatus.wasm" {
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
