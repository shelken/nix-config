# 与旁路由 hk1box（singbox）配合的路由器侧配置，对应 modules/features/network/singbox-config/templates/router.yaml
{
  imports = [
    ./dhcp.nix
    ./firewall.nix
  ];
}
