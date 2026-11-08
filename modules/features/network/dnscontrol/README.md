# dnscontrol

用 [dnscontrol](https://docs.dnscontrol.org/) 声明式管理 Cloudflare 上主域名的 DNS 记录。整份配置 `dnsconfig.js` 用 sops 加密后放在本目录的 `dnsconfig.sops.js`，公开仓库里只有密文。Cloudflare token 在 secrets 仓库

可选功能，只有在 `imports` 里声明的主机才有：当前是 `mio`（`self.modules.darwin.dnscontrol`）

## 用法

```bash
dnscontrol-ctl <preview|push|check|print-ir>
```

| 子命令     | 作用                           |
| :--------- | :----------------------------- |
| `preview`  | 对比线上记录与配置，只显示差异 |
| `push`     | 把差异推到线上，会改线上 DNS   |
| `check`    | 只校验语法，不访问 Cloudflare  |
| `print-ir` | 打印展开后的中间表示，用于调试 |

`dnscontrol-ctl` 没有 `just` 别名，也不接 CI 和系统激活：`push` 改线上 DNS，必须先看 `preview`。`just dns::edit` 只用来编辑密文，不碰线上

## 改记录

1. 编辑密文，保存时 sops 自动重新加密
   ```bash
   just dns::edit
   ```
2. `just hm`，让 sops-nix 把新配置解密到 `~/.config/dnscontrol/dnsconfig.js`
3. `dnscontrol-ctl preview`，确认差异符合预期
4. `dnscontrol-ctl push`
5. 提交 `dnsconfig.sops.js`

扩展名用 `.js` 是为了 `sops` 打开的临时文件被编辑器按 JavaScript 高亮；sops 对未知扩展名按 binary 处理。仓库内的 `.prettierignore` 已排除它

没有 `liveEdit`：配置只存在于密文，解密副本由激活步骤生成。密文是整块数据，PR 里看不到记录的改动

## 漂移检查

`dnscontrol-ctl preview` 输出为空，说明线上记录与配置一致。输出非空且不是自己刚改的，说明有人在 Cloudflare 面板里手改过

## 密钥

| 内容                 | 位置                                                    |
| :------------------- | :------------------------------------------------------ |
| `dnsconfig.js`       | 本目录 `dnsconfig.sops.js`，接收者见仓库根 `.sops.yaml` |
| Cloudflare API token | secrets 仓库的 `dnscontrol/cloudflare-api-token`        |

token 是专用的，权限只给 Zone:DNS:Edit 与 Zone:Read，不复用 Caddy 的 ACME token

密文进了 git 历史就撤不回。`.sops.yaml` 里的接收者变动后，用 `sops updatekeys` 更新密文，旧历史里的密文仍可被旧密钥解开

## 实现

- `_dnscontrol.nix`：用 sops-nix 把 `dnsconfig.sops.js` 解密到 `~/.config/dnscontrol/dnsconfig.js`，链接 `creds.json`，用 mise 安装 dnscontrol `5.2.0`（nixpkgs 版本是 4.x），生成 `dnscontrol-ctl`
- `dnscontrol-ctl.sh`：读 token，`exec mise exec -- dnscontrol`。读不到配置或 token 时报「本机未启用 secrets，或还没激活过」
