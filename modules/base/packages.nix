{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    tealdeer # a very fast version of tldr
    fastfetch
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
    yj # for mylibx

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
}
