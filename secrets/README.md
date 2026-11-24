# 凭据管理架构 (Secrets & SOPS)

本项目使用 [sops-nix](https://github.com/Mic92/sops-nix) 与 [age](https://github.com/FiloSottile/age) 管理加解密，源密文存放在私有仓库 [secrets.nix](https://github.com/shelken/secrets.nix)

## 核心设计原则

- **SSH 与 Age 密钥解耦**：网络登录用 SSH 密钥（在 `secrets.nix` 执行 `just rotate ssh` 轮换），配置解密用独立原生 Age 根密钥（私钥 `~/.config/sops/age/keys.txt`，公钥声明在 `secrets.nix/.sops.yaml`），互不影响
- **`sec-run` 本进程解析后 `exec` 目标命令**（不直接 `exec op run`）：
  - 单条失效引用可剔除重试，不会像 `op run` 那样整体失败
  - SOPS 解出的 service account token 仅在子 shell 中传给 `op`，不残留给目标命令
  - 目标命令直接接管终端，避免 `op run` 代理破坏 TUI 的 tty 探测与 `SIGWINCH`
- **`$HOME/.specific.zsh` 凭据覆盖层**：
  - 仅放相对凭据基座（`opSecretMap`）的临时覆盖，用 `sec-env add KEY "op://Agent/<条目>/credential"` 写入，注释或 `sec-env del KEY` 回落
  - `op://` 引用仅限 `Agent` vault（`sec-run` 使用只读 service account，无法访问其他 vault），迁移期允许明文但不推荐
  - 长期换值直接修改 1Password 条目，不动本地文件

## 密钥初始化与编辑

```shell
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
age-keygen -y ~/.config/sops/age/keys.txt   # 公钥填入 secrets.nix/.sops.yaml
```

在 `secrets.nix` 中编辑密文：`sops sops/secrets/shelken/default.yaml`

## 日常维护

- 轮换 Age 根密钥：在 `secrets.nix` 根目录执行 `just rotate age`
- 本地联调 `secrets.nix` 改动：在 `nix-config` 执行 `just hm-dev`
