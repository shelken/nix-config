{
  inputs,
  lib,
  myvars,
  hosts,
  ...
}:
let
  nuciVersion = (lib.importTOML "${inputs.openwrt-nix}/Cargo.toml").package.version;
  openwrtHosts = lib.filterAttrs (_: host: host.type == "openwrt") hosts;
in
{
  flake.modules.homeManager.openwrt.programs.mise.globalConfig.tools."github:lonerOrz/openwrt-nix" =
    nuciVersion;

  flake.modules.nixos.openwrt-builder =
    { pkgs, ... }:
    let
      runner = pkgs.writeShellScript "openwrt-imagebuild-runner" (
        builtins.readFile ./imagebuild-remote.sh
      );

      openwrtImagebuild = pkgs.buildFHSEnv {
        name = "openwrt-imagebuild";
        targetPkgs =
          p: with p; [
            bash
            bzip2
            coreutils
            curl
            diffutils
            file
            findutils
            gawk
            gnugrep
            gnumake
            gnupatch
            gnused
            gnutar
            gzip
            jq
            perl
            python3
            rsync
            unzip
            util-linux
            wget
            which
            xz
            zlib
            zstd
          ];
        runScript = "${runner}";
      };
    in
    {
      environment.systemPackages = [ openwrtImagebuild ];

      systemd.tmpfiles.rules = [
        "d /var/cache/openwrt-imagebuilder 0755 root root -"
        "d /var/cache/openwrt-imagebuilder/tarballs 0755 root root 90d"
        "d /var/cache/openwrt-imagebuilder/dl 0755 root root 30d"
        "d /var/cache/openwrt-imagebuilder/out 0755 root root 7d"
      ];
    };

  perSystem =
    { pkgs, ... }:
    let
      uci = pkgs.callPackage "${inputs.openwrt-nix}/nix" { };
    in
    {
      packages =
        lib.mapAttrs' (
          name: host:
          lib.nameValuePair "${name}-uci" (
            (uci.writeUci {
              imports = host.uci-modules ++ [ { _module.args = { inherit inputs myvars; }; } ];
            }).json.overrideAttrs
              (old: {
                passthru = (old.passthru or { }) // {
                  sopsFile = inputs.secrets + "/sops/secrets/hosts/${name}.yaml";
                };
              })
          )
        ) openwrtHosts
        // lib.mapAttrs' (
          name: host:
          let
            fw = host.firmware;
            targetSlug = lib.replaceStrings [ "/" ] [ "-" ] fw.target;
            baseUrl = "https://downloads.immortalwrt.org/releases/${fw.version}/targets/${fw.target}";
            tarball = "immortalwrt-imagebuilder-${fw.version}-${targetSlug}.Linux-x86_64.tar.zst";
          in
          lib.nameValuePair "${name}-firmware" (
            (pkgs.writeText "${name}-firmware.json" (builtins.toJSON fw)).overrideAttrs {
              passthru.imagebuilder = {
                inherit tarball;
                url = "${baseUrl}/${tarball}";
                sha256sumsUrl = "${baseUrl}/sha256sums";
              };
            }
          )
        ) (lib.filterAttrs (_: host: host ? firmware) openwrtHosts);
    };
}
