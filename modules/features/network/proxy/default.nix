{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.proxy ];
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.proxy-client ];

  flake.modules.homeManager.proxy =
    { config, lib, ... }:
    let
      proxyFunctions = ''
        function proxy() {
          local default_proxy="http://127.1:7890"
          local final_proxy="''${PROXY:-$default_proxy}"

          export HTTP_PROXY="$final_proxy"
          export HTTPS_PROXY="$final_proxy"
          export http_proxy="$final_proxy"
          export https_proxy="$final_proxy"

          echo "✅ 代理设置完成："
          echo "  HTTP_PROXY:  $HTTP_PROXY"
          echo "  HTTPS_PROXY: $HTTPS_PROXY"
        }
        function unproxy() {
          unset PROXY https_proxy http_proxy HTTPS_PROXY HTTP_PROXY
        }
      '';
    in
    {
      home.file.".proxychains/proxychains.conf".source = ./proxychains.conf;
      programs.zsh.initContent = lib.mkIf config.programs.zsh.enable (lib.mkOrder 1001 proxyFunctions);
      programs.bash.initExtra = lib.mkIf config.programs.bash.enable (lib.mkOrder 1001 proxyFunctions);
    };

  flake.modules.darwin.proxy-client.homebrew.casks = [
    "sfm"
  ];
}
