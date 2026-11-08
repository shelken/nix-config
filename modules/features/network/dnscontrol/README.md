# dnscontrol

用 [dnscontrol](https://docs.dnscontrol.org/) 声明式管理 Cloudflare 上主域名的 DNS 记录。仓库里没有域名、公网 IP 和 token，它们都在 sops，由 `dnscontrol-ctl` 在运行时注入

可选功能，只有在 `imports` 里声明的主机才有：当前是 `mio`（`self.modules.darwin.dnscontrol`）

## 用法

```bash
dnscontrol-ctl <preview|push|check|print-ir>
```

| 子命令     | 作用                                             |
| :--------- | :----------------------------------------------- |
| `preview`  | 对比线上记录与 `config/dnsconfig.js`，只显示差异 |
| `push`     | 把差异推到线上，会改线上 DNS                     |
| `check`    | 只校验语法与变量，不访问 Cloudflare              |
| `print-ir` | 打印展开后的中间表示，用于调试                   |

没有 `just` 别名，也不接 CI 和系统激活：`push` 改线上 DNS，必须先看 `preview`

## 改记录

1. 改 `config/dnsconfig.js`。开发机开启 `shelken.dotfiles.liveEdit` 时配置目录是软链，不用 `just hm`
2. `dnscontrol-ctl preview`，确认差异符合预期
3. `dnscontrol-ctl push`
4. 提交

## 漂移检查

`dnscontrol-ctl preview` 输出为空，说明线上记录与配置一致。输出非空且不是自己刚改的，说明有人在 Cloudflare 面板里手改过

`config/dnsconfig.js` 里的 `IGNORE(...)` 列出了不归它管的记录（cf tunnel、external-dns、ddns 等），这些记录的差异不会出现在 `preview`

## 变量与 sops 键

`dnsconfig.js` 直接引用全局变量，缺任何一个，dnscontrol 解析时立即报错。变量经 `dnscontrol-ctl` 用 `-v` 传入，token 经环境变量 `CLOUDFLARE_API_TOKEN` 传给 `config/creds.json`

| 变量 / 环境变量        | sops 键                           | 内容                                            |
| :--------------------- | :-------------------------------- | :---------------------------------------------- |
| `domain`               | `main-domain`                     | 主域名，与其他功能共用                          |
| `vps_v4`               | `dnscontrol/vps-ipv4`             | VPS 公网 IPv4                                   |
| `vps_v6`               | `dnscontrol/vps-ipv6`             | VPS 公网 IPv6                                   |
| `vps_v6_secondary`     | `dnscontrol/vps-ipv6-secondary`   | `vps` 的第二个 AAAA                             |
| `cf_dcv_id`            | `dnscontrol/cf-dcv-id`            | `_acme-challenge.blog` 的 Cloudflare DCV 标识   |
| `CLOUDFLARE_API_TOKEN` | `dnscontrol/cloudflare-api-token` | 专用 token，权限只给 Zone:DNS:Edit 与 Zone:Read |

键在 secrets 仓库的 `sops/secrets/<用户名>/default.yaml`，声明在 `_dnscontrol.nix`。token 不复用 Caddy 的 ACME token

## 实现

- `_dnscontrol.nix`：声明 sops 密钥，用 mise 安装 dnscontrol `5.2.0`（nixpkgs 版本是 4.x），把 `config/` 软链到 `~/.config/dnscontrol`，生成 `dnscontrol-ctl`
- `dnscontrol-ctl.sh`：读 sops 密文，组装 `-v` 参数，`exec mise exec -- dnscontrol`。读不到密文时报「本机未启用 secrets，或还没激活过」

`dnscontrol-ctl.sh` 的逻辑改动需要 `just hm`，因为脚本经 Nix 包装
