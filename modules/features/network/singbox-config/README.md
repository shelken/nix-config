# singbox-config

## 生成订阅 URL

```bash
singbox-config <mac|ios|router>
```

改模板后先 `just hm` 让已安装生成器指向新模板再执行；router 的 URL 写入 secrets 仓库 `sops/secrets/hosts/hk1box.yaml` 的 `sing-box-sub-url`（见 `hosts/hk1box/README.md`）。仅模板、节点或 `clash-secret` 变化时需要重新生成，改白名单不用

## 路由端 overlay 与约定

- `dns.servers` 的 `dns-lan`：填主路由地址。底模路由角色不含 `fragments/base/dns-lan-resolver.json`（`type: local` 仅对 `*.local` 走内置 mDNS），底模五处 DNS 规则与 `route.default_domain_resolver` 都依赖此 tag，缺失会导致配置无法启动
- `clash_api.external_controller`：路由底模已监听 `0.0.0.0:9090`，overlay 再显式声明以便与 `secret` 集中管理
- `int.<域名>` 不再配固定应答：已登记在 proxy 仓库 `MyDirect.yaml`，经 `MyDirect-dns → dns-lan` 由主路由 dnsmasq 应答；前提失效时按 proxy 仓库 ADR-0014 把 `fragments/base/dns-deployment.json` 加回 `roles.router`
- 名单内设备的网关指向这台，可使用盒子 DNS 或经盒子访问公网 DNS；发给主路由的 DNS 查询不在本方案接管范围内
