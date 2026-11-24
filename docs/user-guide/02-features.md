# 功能与角色

角色分工见 [GLOSSARY.md](../../GLOSSARY.md) 与 [modules/profiles/](../../modules/profiles/)，写法规则见 [software-config.md](../agents/software-config.md)、[ADR 0004](../adr/0004-dendritic-feature-modules.md) 与 [ADR 0012](../adr/0012-feature-domains-and-file-form.md)

## 加一个软件

1. 新建 `modules/features/<分类>/<名>.nix`（含非 nix 资源时建 `<名>/default.nix`）：

   ```nix
   { config, ... }:
   {
     flake.modules.darwin.desktop.imports = [ config.flake.modules.darwin.foo ];
     flake.modules.darwin.foo.homebrew.casks = [ "foo" ];
     flake.modules.homeManager.foo = { config, mylib, ... }: {
       xdg.configFile."foo/config.toml" = mylib.mkConfigFile config ./foo.toml;
     };
   }
   ```

2. `git add` 新文件后运行 `just bd` 验证

- 配置文件用 `mylib.mkConfigFile config ./文件` 引入
- 纯 Home Manager 功能挂 `homeManager.<角色>.imports`；已有同名系统模块的不要重复挂，也不要同时挂角色与主机

## 给某台主机加可选功能

用 `just unused` 查看未挂入主机的模块，在主机 `imports` 中显式引入（NixOS 用 `self.modules.nixos.<名>`）：

```nix
# hosts/sakamoto/default.nix
imports = with self.modules.darwin; [ desktop homelab utm ];
```

## 调整主机参数

常用选项写在主机 `shelken` 下，比如 `shelken.secrets.enable = true`（`default.nix`）或 `shelken.dotfiles.liveEdit = true`（`home.nix`），查全部选项：

```bash
rg 'options\.shelken' modules/features/
```

## 新增一台主机

1. 复制同类主机目录（比如 `hosts/ling/`），改 `hostname` 与 `imports` 角色
2. 在 `hosts/default.nix` 登记新主机
3. 需要密钥时按根目录 [README](../../README.md)「初始化」加公钥，并开 `shelken.secrets.enable = true`
4. 执行 `git add hosts/<主机>` 与 `just b <主机>` 验证
