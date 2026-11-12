# home-ops 的 DNS：集群域转给 k8s-gateway，集群外自举名由路由器本地应答。
# 是返回 dnsmasq 段选项的函数，由 network/dhcp.nix 并入（该段是匿名段，不能由别的文件补字段）。
# 自举名与 hosts/sakamoto 的 Caddyfile 里 internal-access 的站点一一对应
{ bootstrapAddress }:
let
  bootstrapNames = [
    "rustfs-ui"
    "rustfs"
    "nvidia-dls"
    "pve-mine"
    "ghcr-mirror"
    "quay-mirror"
    "mirror-gcr-mirror"
    "k8s-mirror"
  ];
in
{
  server = [
    "/ooooo.space/192.168.69.41"
    "/int.ooooo.space/192.168.69.41"
  ];

  # address_as_local 让每条 address 同时是 local=：A、AAAA 都在本地闭合，
  # 集群挂了也能解析，不会把 AAAA 查询转发给 k8s-gateway 而超时
  address_as_local = "1";
  address = map (name: "/${name}.int.ooooo.space/${bootstrapAddress}") bootstrapNames;
}
