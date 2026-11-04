{
  config,
  lib,
  myvars,
  pkgs,
  ...
}:
#############################################################
#
#  homepage-labels：把容器声明里的 homepage.* 标签渲染成 Homepage 直接能吃的列表
#
#  Homepage 的 docker 集成只从列表接口读 Id / Names / State / Labels，health 只能靠
#  filters 区分（其源码注释：docker exposes health only as a filter on the list
#  endpoint, never as a field）。所以这里不接 Docker、不开 socket，只把同一份声明
#  渲染成同样形状的响应，由 caddy 以静态文件提供给 tailnet 侧。
#  于是那个按 API 段放行、连 inspect（能读到容器 env）都放行的只读代理不再需要。
#
#############################################################
let
  address = myvars.networking.hostAddress."vps-cc-ts".address;

  labelled = lib.filterAttrs (
    _: container: (container.labels or { }) ? "homepage.name"
  ) config.virtualisation.oci-containers.containers;

  entries = lib.mapAttrsToList (name: container: {
    # 稳定且唯一：Homepage 用它做状态表的键
    Id = builtins.hashString "sha256" name;
    Names = [ "/${name}" ];
    Image = container.image;
    State = "running"; # 声明态；真实存活由 Gatus 负责
    Status = "declared";
    Labels = container.labels;
  }) labelled;

  serveDir = pkgs.linkFarm "homepage-docker-labels" [
    {
      name = "containers/json";
      path = pkgs.writeText "containers.json" (builtins.toJSON entries);
    }
  ];
in
{
  # 往已声明的 caddy 容器上并列表：list 类型的选项会自动合并
  virtualisation.oci-containers.containers.caddy = {
    volumes = [ "${serveDir}:/srv/homepage-docker:ro" ];
    ports = [ "${address}:2576:2576/tcp" ];
  };
}
