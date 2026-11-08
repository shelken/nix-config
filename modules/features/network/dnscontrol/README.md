# dnscontrol

用 [dnscontrol](https://docs.dnscontrol.org/) 声明式管理 Cloudflare 上主域名的 DNS 记录。整份配置用 sops 加密后放在本目录的 `dnsconfig.sops.js`，公开仓库里只有密文。Cloudflare token 在 secrets 仓库

可选功能，只有在 `imports` 里声明的主机才有：当前是 `mio`（`self.modules.darwin.dnscontrol`）。本功能只负责安装 dnscontrol 并放置 token，操作入口是 `just dns::<配方>`，定义在 `just/dns.just`

## 用法

| 命令                | 作用                               |
| :------------------ | :--------------------------------- |
| `just dns::edit`    | 编辑加密的配置，保存时自动重新加密 |
| `just dns::preview` | 对比线上记录与配置，只显示差异     |
| `just dns::push`    | 把差异推到线上，会改线上 DNS       |

没有全局命令：改记录之后手动操作，日常很少用，不值得装进 PATH，也不接 CI 和系统激活。`push` 改线上 DNS，必须先看 `preview`

## 改记录

1. `just dns::edit`
2. `just dns::preview`，确认差异符合预期
3. `just dns::push`
4. 提交 `dnsconfig.sops.js`

配置由 sops 直接从密文解密，经 FIFO 交给 dnscontrol，明文不落盘。所以改完不用 `just hm`

扩展名用 `.js` 是为了 `sops` 打开的临时文件被编辑器按 JavaScript 高亮；sops 对未知扩展名按 binary 处理。仓库内的 `.prettierignore` 已排除它

密文是整块数据，PR 里看不到记录的改动。提交信息也不要写具体改了哪条记录

## 漂移检查

`just dns::preview` 输出为空，说明线上记录与配置一致。输出非空且不是自己刚改的，说明有人在 Cloudflare 面板里手改过

## 密钥

| 内容                 | 位置                                                    |
| :------------------- | :------------------------------------------------------ |
| DNS 配置             | 本目录 `dnsconfig.sops.js`，接收者见仓库根 `.sops.yaml` |
| Cloudflare API token | secrets 仓库的 `dnscontrol/cloudflare-api-token`        |

token 是专用的，权限只给 Zone:DNS:Edit 与 Zone:Read，不复用 Caddy 的 ACME token。激活后落在 `~/.config/dnscontrol/cloudflare-api-token`，`just dns::preview` 与 `push` 经环境变量 `CLOUDFLARE_API_TOKEN` 交给 `creds.json`。读不到时报「本机未启用 secrets，或还没激活过」

密文进了 git 历史就撤不回。`.sops.yaml` 里的接收者变动后，用 `sops updatekeys` 更新密文，旧历史里的密文仍可被旧密钥解开

## 实现

- `_dnscontrol.nix`：用 mise 安装 dnscontrol `5.2.0`（nixpkgs 版本是 4.x），用 sops-nix 把 token 放到固定路径
- `just/dns.just`：编辑、preview、push 三个配方，`preview` 与 `push` 共用一个私有配方，读 token 后用 `sops exec-file` 解密配置并调用 `mise exec -- dnscontrol`
