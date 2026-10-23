# 全平台系统级 CLI 基础包（modules/base/packages.nix 迁入）
# darwin 与 nixos 用同一份包列表；flake-parts 顶层拿不到 pkgs，
# 以 specialArgs 之外的方式：包列表提出为 let，pkgs 由系统模块自己的参数提供
{
  flake.modules.darwin.system-packages =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        tealdeer # a very fast version of tldr
        just
        neovim
        git # used by nix flakes
        # git-lfs # used by huggingface models

        # archives
        zip
        xz
        zstd
        unzip
        p7zip

        # Text Processing
        # Docs: https://github.com/learnbyexample/Command-line-text-processing
        gnugrep # GNU grep, provides `grep`/`egrep`/`fgrep`
        # gnused
        gawk # GNU awk, a pattern scanning and processing language
        jq # A lightweight and flexible command-line JSON processor
        # yj

        # networking tools
        mtr # A network diagnostic tool
        iperf3
        wget
        curl
        socat # replacement of openbsd-netcat
        nmap # A utility for network discovery and security auditing

        # misc
        file
        which
        tree
        rsync
      ];
    };

  flake.modules.nixos.system-packages =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        tealdeer # a very fast version of tldr
        just
        neovim
        git # used by nix flakes
        # git-lfs # used by huggingface models

        # archives
        zip
        xz
        zstd
        unzip
        p7zip

        # Text Processing
        # Docs: https://github.com/learnbyexample/Command-line-text-processing
        gnugrep # GNU grep, provides `grep`/`egrep`/`fgrep`
        # gnused
        gawk # GNU awk, a pattern scanning and processing language
        jq # A lightweight and flexible command-line JSON processor
        # yj

        # networking tools
        mtr # A network diagnostic tool
        iperf3
        wget
        curl
        socat # replacement of openbsd-netcat
        nmap # A utility for network discovery and security auditing

        # misc
        file
        which
        tree
        rsync
      ];
    };
}
