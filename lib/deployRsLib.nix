# deploy-rs 的 lib（activate、deployChecks），按系统各一份
# 上游 lib 的激活器从 deploy-rs 源码编译，公共 cache 没有，部署时要现编 Rust（#184）。
# 照 deploy-rs README 的做法：保留它的 lib，只把激活器换成 nixpkgs 自带的包（cache.nixos.org 有）。
# 这样 Mac 上的 deploy 命令与目标机上的激活器都来自同一份 nixpkgs。
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
