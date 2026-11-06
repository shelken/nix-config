# singbox-config

把 mac / ios / router 三份 sbtools 配置声明式管起来，生成订阅 URL。脚本 `singbox-config.sh` 填充 `templates/<变体>.yaml` 里的 1Password 引用，再交给 `sbtools encode`（订阅服务地址取 sops 的 `main-domain`）；私密值只落在临时目录，仓库与 nix store 里没有明文。

## 生成订阅 URL

```bash
singbox-config <mac|ios|router>
```

改模板后先 `just hm`，让已安装的生成器指向新模板，再生成。router 的 URL 要写进 secrets 仓库 `sops/secrets/hosts/hk1box.yaml` 的 `sing-box-sub-url`（见 `hosts/hk1box/README.md`）。

只有模板、节点或 `clash-secret` 变了才需要重新生成。改白名单不用。

## 路由端：白名单

白名单设备的源 IP 写在 `hosts/hk1box/sing-box.nix` 的 `whitelist`：已在 `vars/networking.nix` 登记的设备引用它的 `address`，没登记的写 IP，与 `vars/networking.nix` 同一网段。`templates/router.yaml` 的 DNS 与 route 两处列表只留占位符 `"source_ip_cidr": "@whitelist@"`，盒子每次拉取订阅后替换。改名单只改这一处并部署，不用重新生成订阅 URL

## DNS 归属与放行

底模只留与部署无关的策略，本网解析器地址、放行（不被改写）的解析器清单、白名单三项与 clash API 的监听地址都由 `templates/router.yaml` 的 overlay 提供：

| overlay 内容                    | 作用                                                                                                                                                                                                                                                                                                                                                                |
| :------------------------------ | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `dns.servers` 的 `dns-lan`      | 本网解析器，填主路由地址。底模的路由角色不列这份能力（`roles.router` 里没有 `fragments/base/dns-lan-resolver.json`；`type: local` 对 `*.local` 固定走内置 mDNS），地址只能由这里给；底模的 `Lan-dns`、`local` / `lan` / `home.arpa`、`MyDirect-dns`、`clash_mode: direct`、`PTR` 五处 DNS 规则与 `route.default_domain_resolver` 都指向这个 tag，缺了配置直接起不来 |
| `clash_api.external_controller` | 路由底模（`fragments/router/experimental.json`）已监听 `0.0.0.0:9090`，这里再显式写一遍，让对局域网的监听与 `secret` 一起收在 overlay                                                                                                                                                                                                                               |
| `route.rules` 的放行解析器规则  | 发往清单内解析器的查询不进本机 DNS，由内核直接放行；该解析器对内网域的负向应答不再被本机改写                                                                                                                                                                                                                                                                        |
| 白名单                          | 名单外设备的连接在 `auto_redirect` 预匹配阶段被旁路，由内核直接转发，不进 sing-box                                                                                                                                                                                                                                                                                  |

部署域 `int.ooooo.space` 不再需要固定应答：它已登记在 proxy 仓库的 `config/rules/custom/MyDirect.yaml`（覆盖 `ooooo.space` 全部子域），随底模的 `MyDirect-dns → dns-lan` 交给主路由 dnsmasq 应答，与主路由上的固定租约天然一致。已在局域网内实测前提成立：`dig @192.168.6.1 cpa.int.ooooo.space A` → `192.168.69.46`，`dig @192.168.6.1 int.ooooo.space` → 无应答（与底模那两条规则的效果一致）；不成立时按 proxy 仓库 ADR-0014 的回退，把 `fragments/base/dns-deployment.json` 加进 `roles.router`

`route.rules` 的三条顺序固定为「放行解析器 → 53 劫持 → 白名单 `bypass`」：第一条要给设备显式指定的解析器留出口，白名单那条匹配的是「不在名单里」的整台设备，换序会把名单外设备的 DNS 一起放走。

- 名单外设备在 `auto_redirect` 预匹配阶段被 `bypass`，内核直接转发给主路由，不进 sing-box
- 名单内设备的网关指向这台，可使用盒子 DNS 或经盒子访问公网 DNS；发给主路由的 DNS 查询不在本方案接管范围内
- DNS 白名单按源 IP 匹配，名单外设备即使把 DNS 指向盒子，也不会拿到盒子的 fakeip
- 手机等设备开随机 MAC 不影响识别；白名单按 IP 匹配，需在主路由给设备配固定租约
