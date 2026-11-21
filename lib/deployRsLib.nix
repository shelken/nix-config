{
  lib,
  nixpkgs,
  deploy-rs,
  systems,
}:
lib.genAttrs systems (
  system:
  (import nixpkgs {
    inherit system;
    overlays = [
      # deploy-rs 的 overlay 会把 deploy-rs 这个名字换成 { deploy-rs; lib; }，先把 nixpkgs 原来的包另存
      (_: prev: { deploy-rs-nixpkgs = prev.deploy-rs; })
      deploy-rs.overlays.default
      (final: prev: {
        deploy-rs = prev.deploy-rs // {
          deploy-rs = final.deploy-rs-nixpkgs;
        };
      })
    ];
  }).deploy-rs.lib
)
