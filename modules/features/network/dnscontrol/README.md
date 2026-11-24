# dnscontrol

用 [dnscontrol](https://docs.dnscontrol.org/) 声明式管理 Cloudflare 主域名 DNS 记录，密文存放在 `dnsconfig.sops.js`。模块仅安装 `dnscontrol-cf` 供 `just dns::*` 调用，日常不直接调用全局命令，也不接 CI 或系统激活

## 改记录

1. `just dns::edit`（编辑加密配置，保存自动重加密）
2. `just dns::preview`（确认差异；`Done. 0 corrections.` 表示线上一致）
3. `just dns::push`（先看 `preview` 再推线上）
4. 提交 `dnsconfig.sops.js`

- 配置经 sops FIFO 直接解密交给 dnscontrol，明文不落盘，改完无需 `just hm`
- 扩展名用 `.js` 是为了让 `sops` 打开的临时文件按 JavaScript 高亮（sops 对未知后缀按 binary 处理），已加入 `.prettierignore`
- 密文为整块数据，PR 与提交信息均不要写具体改了哪条记录

## 密钥

- Cloudflare API token 存放在 1Password `Projects/nix-config` 的 `cloudflare-dnscontrol-token` 字段，仅授予 `Zone:DNS:Edit` 与 `Zone:Read`，不复用 Caddy 的 ACME token
- 运行时通过 `env -u OP_SERVICE_ACCOUNT_TOKEN op read` 经 1Password 桌面 App + Touch ID 读取，不落盘且不串入 Agent service account
- `.sops.yaml` 接收者变动后用 `sops updatekeys` 更新密文（git 历史中旧密文仍可被旧密钥解开）
