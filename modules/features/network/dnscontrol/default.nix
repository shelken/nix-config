# dnscontrol：用声明式配置管理 Cloudflare 上的 DNS 记录
#
# 整份 dnsconfig.js（域名、IP、全部记录）用 sops 加密后放在本目录，只有 API token 在 secrets 仓库；
# 本功能只负责安装 dnscontrol 与放置 token，日常操作走 just dns::<配方>，用法见 README.md
#
# 可选功能：要用的主机在 imports 里加 self.modules.darwin.dnscontrol（NixOS 主机同理）
{
  flake.modules.homeManager.dnscontrol.imports = [ ./_dnscontrol.nix ];
}
