{
  config,
  lib,
  myvars,
  pkgs,
  ...
}:
#  Homepage 的 docker 集成只从列表接口读 Id / Names / State / Labels，health 只能靠
#  filters 区分（其源码注释：docker exposes health only as a filter on the list
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
    State = "running";
    Status = "declared";
    Labels = container.labels;
  }) labelled;

  # 用 writeTextDir 而不是 linkFarm：linkFarm 只产出指向别处的符号链接，单独把这个
  # 目录挂进容器后链接目标不存在，file_server 会 404
  serveDir = pkgs.writeTextDir "containers/json" (builtins.toJSON entries);
in
{
  virtualisation.oci-containers.containers.caddy = {
    volumes = [ "${serveDir}:/srv/homepage-docker:ro" ];
    ports = [ "${address}:2576:2576/tcp" ];
  };
}
