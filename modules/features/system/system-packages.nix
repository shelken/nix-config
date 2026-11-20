{ config, lib, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.system-packages ];
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.system-packages ];

  flake.modules.darwin.system-packages =
    { pkgs, ... }:
    {
      environment.systemPackages = lib.mkBefore (
        with pkgs;
        [
          tealdeer
          just
          neovim
          git

          zip
          xz
          zstd
          unzip
          p7zip

          gnugrep
          gawk
          jq

          mtr
          iperf3
          wget
          curl
          socat
          nmap

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
      # system-path 开 ignoreCollisions，同路径冲突时排前的包胜出
      environment.systemPackages = lib.mkBefore (
        with pkgs;
        [
          neovim
          git

          zip
          xz
          zstd
          unzip
          p7zip

          gnugrep
          gawk
          jq

          wget
          curl

          file
          which
          tree
          rsync
        ]
      );

      environment.variables.EDITOR = "nvim";
    };
}
