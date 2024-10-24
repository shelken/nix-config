{
  myvars,
  lib,
  pkgs,
  ...
}: let
  theme = "catppuccin-${lib.strings.toLower myvars.catppuccin_flavor}";
  # origin_file = builtins.readFile ./config.kdl;
  keybinds-config = builtins.readFile ./keybinds.kdl;
  inherit (lib) concatStrings;
  zellij-forgot = pkgs.stdenv.mkDerivation rec {
    pname = "zellij-forgot";
    version = "0.4.0";

    src = builtins.fetchurl {
      url = "https://github.com/karimould/zellij-forgot/releases/download/${version}/zellij_forgot.wasm";
      sha256 = "sha256:1hzdvyswi6gh4ngxnplay69w1n8wlk17yflfpwfhv6mdn0gcmlsr";
    };
    phases = ["installPhase"];

    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/zellij_forgot.wasm
    '';
  };
  zjstatus = pkgs.stdenv.mkDerivation rec {
    pname = "zjstatus";
    version = "v0.17.0";

    src = builtins.fetchurl {
      url = "https://github.com/dj95/zjstatus/releases/download/${version}/zjstatus.wasm";
      sha256 = "sha256:1rbvazam9qdj2z21fgzjvbyp5mcrxw28nprqsdzal4dqbm5dy112";
    };
    phases = ["installPhase"];

    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/zjstatus.wasm
    '';
  };
in {
  programs.zellij = {
    enable = true;
    # settings = {
    #   theme = theme;
    # };
    enableBashIntegration = false;
    enableZshIntegration = false;
  };

  xdg.configFile = {
    "zellij/layouts/basic.kdl".text = builtins.readFile ./layouts/basic.kdl;
    "zellij/layouts/basic.swap.kdl".text = builtins.readFile ./layouts/basic.swap.kdl;
    "zellij/config.kdl" = {
      text = concatStrings [
        ''
          // 主题配色
          theme "${theme}"

          default_layout "basic"
          session_serialization true
          simplified_ui false
        ''
        ''
          //键盘绑定
          keybinds {
            ${keybinds-config}

            // 参考：https://github.com/nixypanda/dotfiles/blob/f5d4bb5a1efd006f1db3e29965a12dea09f10356/modules/zellij/default.nix#L56C11-L63C12
            // 插件：命令提示
            shared_except "locked" {
              bind "Ctrl y" {
                LaunchOrFocusPlugin "file:${zellij-forgot}/bin/zellij_forgot.wasm" {
                  "LOAD_ZELLIJ_BINDINGS" "true"
                  floating true
                }
              }
            }
          }
        ''
        # origin_file
        ''
          plugins {
            zjstatus location="file:${zjstatus}/bin/zjstatus.wasm" {
                ${builtins.readFile ./zjstatus/catpuccin.kdl}
            }
          }
        ''
      ];
    };
  };
}
