# dns.nix 是返回 dnsmasq 选项的函数，由 network/dhcp.nix 引用，不在这里导入
{
  imports = [ ./firewall.nix ];
}
