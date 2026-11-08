// 域名、公网 IP 与 Cloudflare DCV 标识不写在仓库里，由 dnscontrol-ctl 经 `-v` 传入；
// 缺任何一个变量，dnscontrol 解析本文件时直接报错。变量清单见同目录 ../README.md
var DSP_CLOUDFLARE = NewDnsProvider("cloudflare")
var REG_CHANGEME = NewRegistrar("none")

D(
  domain,
  REG_CHANGEME,
  DnsProvider(DSP_CLOUDFLARE),
  DefaultTTL(1), // Cloudflare plays tricks with TTLs. Cloudflare uses "1" to mean "auto-ttl";

  // 忽略管理的域名管理
  IGNORE("*", "CNAME", "**.cfargotunnel.com."), // 忽略 cf tunnel 的 CNAME 记录
  IGNORE("*", "CNAME", "**.r2.dev."), // 忽略 r2 的 CNAME 记录
  IGNORE("*", "NS", "**"), // 忽略所有 NS 记录
  // IGNORE("*", "TXT", "**"), // 忽略所有 TXT记录
  IGNORE("k8s.**", "TXT", "**"), // 忽略所有 k8s 管理 的 TXT 记录
  // k8s
  IGNORE("*", "CNAME", "homelab-external.*"), // external-dns
  IGNORE("*", "CNAME", "homelab-internal.*"), // external-dns
  IGNORE("homelab-external", "CNAME", "homelab-dynamic.*"), // external-dns
  IGNORE("homelab-dynamic", "AAAA", "*"), // 由 ddns 管理
  IGNORE("ss-rust", "AAAA", "*"), // 由 ddns 管理

  // A，AAAA 记录
  A("@", vps_v4, CF_PROXY_ON),
  A("hysteria2", vps_v4),
  A("vps", vps_v4),
  AAAA("vps", vps_v6),
  AAAA("vps", vps_v6_secondary),
  AAAA("@", vps_v6, CF_PROXY_ON),
  AAAA("hysteria2-v6", vps_v6), // hysteria2-v6
  //homelab
  A("homelab-dynamic", vps_v4),

  //CNAME 记录
  CNAME("derp", "vps." + domain + "."),
  CNAME("dhp", "vps." + domain + "."), // docker 镜像代理
  CNAME("sub", "vps." + domain + "."), // 订阅转换
  CNAME("subs", "vps." + domain + "."), // sb-sync-server 配置交付
  CNAME("vdns", "vps." + domain + "."), // mosdns

  //邮件（目前指向腾讯企业邮箱）
  CNAME("mail", "exmail.qq.com."),
  TXT("@", "v=spf1 include:exmail.qq.com ~all"),
  MX("@", 5, "mxbiz1.qq.com."),
  MX("@", 10, "mxbiz2.qq.com."),
  TXT(
    "srrq2512._domainkey",
    "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDL8URju5svRQwa17rPR282+oJpn1fm8yaEVhJVJLPLuIREfMfmkN1D90mGHzbQZYSdOmMS+ZyfnsPjK4SZN5R3+cdZwo6V9BRwkHEnQzmT+cHQxQPnwU3xOULkXtNrCC3Ye/Ltpd47/4kI2yeNrxvCPGpdkbFDqXqvJoydGgZK6wIDAQAB",
  ),
  TXT("_dmarc", "v=DMARC1; p=none; rua=mailto:dmarc-reports@" + domain),

  //xlog
  CNAME("xlog", "cname.xlog.app."),
  TXT("_xlog-challenge.xlog", "shelken"),

  //SAAS 回源加速/优选ip
  CNAME("blog-origin", "shelken.github.io.", CF_PROXY_ON),
  CNAME("blog", "cf.877774.xyz."),
  CNAME(
    "_acme-challenge.blog",
    "blog." + domain + "." + cf_dcv_id + ".dcv.cloudflare.com.",
    CF_PROXY_ON,
  ),
)
