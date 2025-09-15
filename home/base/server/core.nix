{pkgs, ...}: {
  home.packages = with pkgs; [
    #ranger # terminal file manager(batteries included, with image preview support)

    # archives
    zip
    xz
    unzip
    p7zip

    # networking tools
    #mtr # A network diagnostic tool
    #iperf3
    #dnsutils # `dig` + `nslookup`
    #ldns # replacement of `dig`, it provide the command `drill`
    #aria2 # A lightweight multi-protocol & multi-source command-line download utility
    #socat # replacement of openbsd-netcat
    #nmap # A utility for network discovery and security auditing
    #ipcalc # it is a calculator for the IPv4/v6 addresses

    # Text Processing
    # Docs: https://github.com/learnbyexample/Command-line-text-processing
    #gnugrep  # GNU grep, provides `grep`/`egrep`/`fgrep`
    #gnused  # GNU sed, very powerful(mainly for replacing text in files)
    #gawk   # GNU awk, a pattern scanning and processing language
    #ripgrep # recursively searches directories for a regex pattern
    #sad  # CLI search and replace, with diff preview, really useful!!!
    #delta  # A viewer for git and diff output
    # A fast and polyglot tool for code searching, linting, rewriting at large scale
    # supported languages: only some mainstream languages currently(do not support nix/nginx/yaml/toml/...)
    #ast-grep
    #jq # A lightweight and flexible command-line JSON processor
    #yq-go # yaml processor https://github.com/mikefarah/yq

    #cowsay
    file
    which
    tree
    #gnutar
    #zstd
    #caddy
    #gnupg

    # nix related
    #
    # it provides the command `nom` works just like `nix
    # with more details log output
    #nix-output-monitor
    #nodePackages.node2nix

    # productivity
    #hugo # static site generator
    #glow # markdown previewer in terminal

    # A modern, maintained replacement for ls
    eza
  ];
}
