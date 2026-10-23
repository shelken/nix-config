{
  pkgs,
  linuxPkgs,
  gitConfig,
  guestBinPath ? null,
}:
let
  tools = with linuxPkgs; [
    bashInteractive
    coreutils
    bubblewrap
    iproute2
    iptables
    jq
    gnused
    git
    curl
    ripgrep
    fd
    findutils
    gawk
  ];
  defaultPathEnv = "${linuxPkgs.lib.makeBinPath tools}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
  finalBinPath = if guestBinPath != null then guestBinPath else defaultPathEnv;
in
# launcher 正文在 launcher.sh：Linux 版 writeShellApplication 打包，构建期过 shellcheck。
# Nix 只注入 guest PATH 与 git 配置；源文件 shebang 去掉（打包器会写自己的）。
"${
  linuxPkgs.writeShellApplication {
    name = "sb-launcher";
    runtimeInputs = tools;
    text = linuxPkgs.lib.removePrefix "#!/usr/bin/env bash\n" (
      linuxPkgs.lib.replaceStrings [ "@guest_bin_path@" "@git_config@" ] [ finalBinPath "${gitConfig}" ] (
        builtins.readFile ./launcher.sh
      )
    );
  }
}/bin/sb-launcher"
