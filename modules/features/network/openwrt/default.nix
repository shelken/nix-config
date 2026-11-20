# 可选功能：要操作路由器的主机在 imports 里加 self.modules.darwin.openwrt
{
  inputs,
  lib,
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
              imports = host.uci-modules ++ [ { _module.args = { inherit inputs; }; } ];
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
          lib.nameValuePair "${name}-firmware" (
            pkgs.writeText "${name}-firmware.json" (builtins.toJSON host.firmware)
          )
        ) (lib.filterAttrs (_: host: host ? firmware) openwrtHosts);
    };
}
