{
  pkgs,
  linuxPkgs,
  gitConfig,
  guestBinPath,
}:
let
  tools = with linuxPkgs; [
    bashInteractive
    coreutils
    util-linux
    bubblewrap
    iproute2
    jq
    iptables
    gawk
  ];
  template = import ./_template.nix { lib = linuxPkgs.lib; };
in
# launcher 正文在 launcher.sh：Linux 版 writeShellApplication 打包，构建期过 shellcheck。
# Nix 只注入 guest PATH 与 git 配置；源文件 shebang 去掉（打包器会写自己的）。
"${
  linuxPkgs.writeShellApplication {
    name = "sb-launcher";
    runtimeInputs = tools;
    text = linuxPkgs.lib.removePrefix "#!/usr/bin/env bash\n" (
      template ./launcher.sh {
        guest_bin_path = guestBinPath;
        git_config = gitConfig;
      }
    );
  }
}/bin/sb-launcher"
