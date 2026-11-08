# dnscontrol：用声明式配置管理 Cloudflare 上的 DNS 记录
#
# 域名、公网 IP、DCV 标识与 API token 都在 sops 里，仓库只有变量名；用法见 README.md
#
# 可选功能：要用的主机在 imports 里加 self.modules.darwin.dnscontrol（NixOS 主机同理）
{
  flake.modules.homeManager.dnscontrol.imports = [ ./_dnscontrol.nix ];
}
