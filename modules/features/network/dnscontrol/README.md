# dnscontrol

用 [dnscontrol](https://docs.dnscontrol.org/) 声明式管理 Cloudflare 上主域名的 DNS 记录。整份配置用 sops 加密后放在本目录的 `dnsconfig.sops.js`，公开仓库里只有密文。Cloudflare API token 存放在 1Password

可选功能，只有在 `imports` 里声明的主机才有：当前是 `mio`（`self.modules.darwin.dnscontrol`）。本功能只负责安装 dnscontrol 与包装命令 `dnscontrol-cf`，操作入口是 `just dns::<配方>`，定义在 `just/dns.just`

## 用法

| 命令                | 作用                                 |
| :------------------ | :----------------------------------- |
| `just dns::edit`    | 编辑加密的配置，保存时自动重新加密   |
| `just dns::preview` | 对比线上记录与配置，显示待变更的差异 |
| `just dns::push`    | 把差异推到线上，会改线上 DNS         |

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

`just dns::preview` 有进度输出，不会为空。末尾是 `Done. 0 corrections.`，说明线上记录与配置一致。corrections 不为 0 且不是自己刚改的，说明有人在 Cloudflare 面板里手改过

## 密钥

| 内容                 | 位置                                                                      |
| :------------------- | :------------------------------------------------------------------------ |
| DNS 配置             | 本目录 `dnsconfig.sops.js`，接收者见仓库根 `.sops.yaml`                   |
| Cloudflare API token | 1Password `Projects/nix-config` 条目的 `cloudflare-dnscontrol-token` 字段 |

token 是专用的，权限只给 Zone:DNS:Edit 与 Zone:Read，不复用 Caddy 的 ACME token。运行时由 `dnscontrol-cf` 通过 `env -u OP_SERVICE_ACCOUNT_TOKEN op read` 经 1Password 桌面 App + Touch ID 读取，直接经环境变量 `CLOUDFLARE_API_TOKEN` 交给 `creds.json`，不落盘且不串入 Agent service account

密文进了 git 历史就撤不回。`.sops.yaml` 里的接收者变动后，用 `sops updatekeys` 更新密文，旧历史里的密文仍可被旧密钥解开

## 实现

- `default.nix`：用 mise 安装 dnscontrol（nixpkgs 版本较旧），提供 `dnscontrol-cf` 包装命令在运行时从 1Password 读取 token，并断言主机已启用 `shelken.secrets.enable`（sops 解密 `dnsconfig.sops.js` 依赖本机 age 密钥）
- `just/dns.just`：编辑、preview、push 三个配方，`preview` 与 `push` 共用一个私有配方，用 `sops exec-file` 解密配置并调用 `dnscontrol-cf`
