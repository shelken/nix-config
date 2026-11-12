# OpenWrt 路由器的声明式配置：机器表里 type = "openwrt" 的机器，声明经 nuci 编译成 uci.json，
# 日常操作走 just router::<配方>，用法见 README.md
#
# 可选功能：要操作路由器的主机在 imports 里加 self.modules.darwin.openwrt
{
  inputs,
  lib,
  hosts,
  ...
}:
let
  # 二进制版本取自 flake 输入，编译 uci.json 的 Nix 模块与执行它的 nuci 不会错版
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
      packages = lib.mapAttrs' (
        name: host: lib.nameValuePair "${name}-uci" (uci.writeUci { imports = host.uci-modules; }).json
      ) openwrtHosts;
    };
}
