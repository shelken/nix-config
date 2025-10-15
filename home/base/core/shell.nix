{ config, lib, ... }:
let
  proxy_fun = ''
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

  shellAliases = {
    urldecode = "python3 -c 'import sys, urllib.parse as ul; print(ul.unquote_plus(sys.stdin.read()))'";
    urlencode = "python3 -c 'import sys, urllib.parse as ul; print(ul.quote_plus(sys.stdin.read()))'";

    mkdir = "mkdir -p";
  };

  localBin = "${config.home.homeDirectory}/.local/bin";
  goBin = "${config.home.homeDirectory}/go/bin";
  rustBin = "${config.home.homeDirectory}/.cargo/bin";
  npmBin = "${config.home.homeDirectory}/.npm-global/bin";
  krewBin = "${config.home.homeDirectory}/.krew/bin";

  envExtra = ''
    export PATH="$PATH:${localBin}:${goBin}:${rustBin}:${npmBin}:${krewBin}"
  '';

  initContent = ''
    ${proxy_fun}
    ################
    # 特定机器配置 #
    ################
    [[ -s "$HOME/.specific.zsh" ]] && source $HOME/.specific.zsh
  '';
in
{
  programs.bash = {
    enable = true;
    enableCompletion = true;
    bashrcExtra = envExtra;
    initExtra = lib.mkOrder 1001 initContent;
  };
  programs.zsh = {
    enable = true;
    envExtra = envExtra;
    initContent = lib.mkOrder 1001 initContent;
  };

  home.shellAliases = shellAliases;
}
