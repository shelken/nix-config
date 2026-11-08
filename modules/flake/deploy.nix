{
  self,
  inputs,
  lib,
  config,
  mylib,
  hosts,
  ...
}:
let
  deployHosts = lib.filterAttrs (_: v: v ? deploy) hosts;
  deployLib = mylib.deployRsLib {
    inherit lib;
    inherit (config) systems;
    inherit (inputs) nixpkgs deploy-rs;
  };
in
{
  flake.deploy.nodes = lib.mapAttrs (
    name: v:
    mylib.deployNode {
      inherit deployLib name;
      configuration = (self.darwinConfigurations // self.nixosConfigurations).${name};
      inherit (v) type system;
      extra = v.deploy;
    }
  ) deployHosts;

  # 只在原生系统启用，跨系统会让 nix flake check 尝试交叉构建
  perSystem =
    { system, ... }:
    {
      checks = lib.optionalAttrs (system == "aarch64-darwin") (
        deployLib.${system}.deployChecks self.deploy
      );
    };
}
