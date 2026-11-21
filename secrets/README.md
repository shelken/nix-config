# 凭据管理架构 (Secrets & SOPS)

本项目使用 [sops-nix](https://github.com/Mic92/sops-nix) 配合 [age](https://github.com/FiloSottile/age) 进行系统与用户凭据的加解密管理

> 敏感凭据源密文独立存储在外部私有仓库：[secrets.nix](https://github.com/shelken/secrets.nix)

---

## 1. 核心设计原则

- **职责解耦**：
  - **网络登录归 SSH**：使用各主机与个人的 SSH 密钥对，由 `just rotate ssh`（在 `secrets.nix` 仓库执行）闭环管理
  - **配置解密归 Age**：使用独立的原生 Age 根密钥，由 `~/.config/sops/age/keys.txt` 提供解密私钥，公钥声明在 `secrets.nix/.sops.yaml`
  - 两套密钥完全独立，轮换 SSH 密钥不影响 SOPS 解密，反之亦然
- **配置集中收敛**：
  - 系统内所有用户态凭据与 SOPS 选项统一收敛在 `modules/features/secrets/secrets/default.nix`
  - 明确声明密钥路径：`sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt"`
- **`sec-run` 本进程解析后 `exec` 目标命令**（不直接 `exec op run`）：
  - `op run` 遇到一条无法解析的引用即整体失败；留在本进程解析可以剔除失效引用后重试
  - 从 SOPS 文件读取的 service account token 只在子 shell 中暴露给 `op` 那一次调用，不经脚本注入残留给目标命令（残留会把子命令的 `op` 调用限制在 Agent vault；若调用方环境本身已导出 `OP_SERVICE_ACCOUNT_TOKEN`，`exec` 仍按常规环境变量继承）
  - 目标命令直接接管终端，不经 `op run` 代理（代理会破坏 TUI 的 tty 探测与 `SIGWINCH`）
- **敏感明文字典不进 Nix store**：`scrub-words` 默认从 `~/.config/scrub-words/dict.txt` 读取字典（可用 `--dict` 覆写），因为 Nix store 全局可读

---

## 2. 密钥初始化与编辑

### 初始化本地解密私钥

```shell
mkdir -p ~/.config/sops/age
# 生成独立原生 age 密钥
age-keygen -o ~/.config/sops/age/keys.txt

# 查看对应的 public key (age1...)
age-keygen -y ~/.config/sops/age/keys.txt
```

### 授权与编辑

1. 将获取的 `age1...` 公钥填入 `secrets.nix` 仓库的 `.sops.yaml` 对应机器列表中。
2. 在 `secrets.nix` 仓库中编辑密文：
   ```shell
   sops sops/secrets/shelken/default.yaml
   ```

---

## 3. 日常维护与开发工作流

- **日常轮换 Age 根密钥**：
  在 `secrets.nix` 仓库根目录下执行一键自动化向导：
  ```shell
  just rotate age
  ```
- **本地开发极速联调**：
  在 `secrets.nix` 修改密文后，在 `nix-config` 执行以下命令即可直接读取本地修改构建，无需等待 push 到 GitHub：
  ```shell
  just hm-dev
  ```
