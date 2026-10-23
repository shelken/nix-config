# 全平台系统级 CLI 基础包（modules/base/packages.nix 迁入）
# darwin 与 nixos 用同一份包列表；flake-parts 顶层拿不到 pkgs，
# 以 specialArgs 之外的方式：包列表提出为 let，pkgs 由系统模块自己的参数提供
{ config, lib, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.system-packages ];
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.system-packages ];

  flake.modules.darwin.system-packages =
    { pkgs, ... }:
    {
      # mkBefore：与迁移前的顺序一致——基础包先于 darwin/nixos 其余模块贡献的包，
      # system-path 开 ignoreCollisions，同路径冲突时排前的包胜出
      environment.systemPackages = lib.mkBefore (
        with pkgs;
        [
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
        ]
      );
    };

  flake.modules.nixos.system-packages =
    { pkgs, ... }:
    {
      # mkBefore：与迁移前的顺序一致——基础包先于 darwin/nixos 其余模块贡献的包，
      # system-path 开 ignoreCollisions，同路径冲突时排前的包胜出
      environment.systemPackages = lib.mkBefore (
        with pkgs;
        [
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
        ]
      );
    };
}
