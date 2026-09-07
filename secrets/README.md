# 凭据管理架构 (Secrets & SOPS)

本项目使用 [sops-nix](https://github.com/Mic92/sops-nix) 配合 [age](https://github.com/FiloSottile/age) 进行系统与用户凭据的加解密管理。

> 敏感凭据源密文独立存储在外部私有仓库：[secrets.nix](https://github.com/shelken/secrets.nix)

---

## 1. 核心设计原则

- **职责解耦（心智清晰）**：
  - **网络登录归 SSH**：使用各自主机与个人的 SSH 密钥对，由 `just rotate ssh` 闭环管理。
  - **配置解密归 Age**：使用独立的原生 Age 根密钥，由 `~/.config/sops/age/keys.txt` 提供解密私钥，公钥声明在 `secrets.nix/.sops.yaml`。
  - 两套密钥完全独立，轮换 SSH 密钥绝不影响 SOPS 解密，反之亦然。
- **配置集中收敛**：
  - 系统内所有用户态凭据与 SOPS 选项统一收敛在 `home/base/core/secrets.nix`。
  - 明确声明密钥路径：`sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt"`。

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
