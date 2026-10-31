# 功能与角色

一个软件就是一个「功能」，放在 `modules/features/<分类>/<名>`，系统侧（Homebrew、launchd、defaults）和 Home Manager 部分写在同一处。主机不列具体功能，只选一个「角色」，功能自己声明属于哪个角色。设计原因见 [ADR 0004](../adr/0004-dendritic-feature-modules.md)

## 角色

| 角色          | 包含                                       | 主机            |
| ------------- | ------------------------------------------ | --------------- |
| `core`        | 所有主机共有的基线：能登录、能用 nix       | 被其他角色包含  |
| `server`      | `core` + 常驻服务器职责（仅 NixOS）        | vps-cc          |
| `tui`         | `core` + 终端开发工具                      | work-test       |
| `gui`         | `tui` + 桌面环境与图形应用                 | ling            |
| `desktop`     | `gui` + 日常桌面机共有的软件（仅 darwin）  | yuuko、sakamoto |
| `workstation` | `desktop` + 主力机个人工作流               | mio             |
| `homelab`     | 附加角色：兼做服务器的软件，叠加在主角色上 | yuuko、sakamoto |

主机的角色写在 `hosts/<主机>/default.nix` 的 `imports` 里，例如 `imports = [ self.modules.darwin.workstation ];`

## 加一个软件

1. 新建 `modules/features/<分类>/<名>.nix`，写配置并声明加入哪个角色

   ```nix
   # Foo：一句话说明它是什么
   { config, ... }:
   {
     # 加入 desktop：mio、yuuko、sakamoto 获得它
     flake.modules.darwin.desktop.imports = [ config.flake.modules.darwin.foo ];

     # 系统侧
     flake.modules.darwin.foo.homebrew.casks = [ "foo" ];

     # 用户态：与系统侧同名，会自动跟着进入同一批主机
     flake.modules.homeManager.foo =
       { config, mylib, ... }:
       {
         xdg.configFile."foo/config.toml" = mylib.mkConfigFile config ./foo.toml;
       };
   }
   ```

2. 按想让它出现的主机选角色

   | 想让它出现在                  | 写法                                              |
   | ----------------------------- | ------------------------------------------------- |
   | 所有 darwin 主机              | `flake.modules.darwin.core.imports`               |
   | 所有桌面机（含 ling）         | `flake.modules.darwin.gui.imports`                |
   | mio、yuuko、sakamoto          | `flake.modules.darwin.desktop.imports`            |
   | 只有 mio                      | `flake.modules.darwin.workstation.imports`        |
   | yuuko、sakamoto（服务器职责） | `flake.modules.darwin.homelab.imports`            |
   | NixOS 主机                    | `flake.modules.nixos.<角色>.imports`              |
   | 某一台主机                    | 不加入角色，在该主机的 `imports` 里导入，见下一节 |

3. `git add` 新文件，再运行 `just bd` 构建。没被 git 跟踪的文件 flake 看不到

几条规则：

- 只有 Home Manager 部分的软件也按上述方式编写，通过 `darwin.<角色>.imports` 加入，同名的 `homeManager.<名>` 会自动跟进
- 同一个功能只能有一条导入路径：加入角色后勿在主机中重复导入，反之亦然；重复导入会导致 option 重复声明或列表重复
- 配置文件使用 `mylib.mkConfigFile config ./文件`，路径相对当前文件；开启 `shelken.dotfiles.liveEdit` 的主机会软链到仓库源文件，修改后无需重新构建
- 功能较复杂时可组织为目录：以 `modules/features/<分类>/<名>/default.nix` 作为入口，私有片段以 `_` 开头命名（如 `_hm.nix`），不会被自动导入

## 给某台主机加可选功能

可选功能没有加入任何角色，导入了才生效。列出带「可选功能」标记的功能：

```bash
grep -rlE '^# .*可选功能' modules/features
```

打开对应文件，找到 `flake.modules.darwin.<名>` 里的 `<名>`（不一定等于文件名，比如 `game/main.nix` 是 `game-main`），加到主机的 `imports`：

```nix
# hosts/sakamoto/default.nix
imports = with self.modules.darwin; [
  desktop
  homelab
  virts
];
```

NixOS 主机用 `self.modules.nixos.<名>`

## 调整主机参数

参数写在主机文件的 `shelken` 属性集下，未指定时采用默认值

| 选项                        | 写在          | 默认值           | 作用                                                                              |
| --------------------------- | ------------- | ---------------- | --------------------------------------------------------------------------------- |
| `secrets.enable`            | `default.nix` | `false`          | 主机持有 age 密钥；kopia 备份等需要密钥的功能依赖它，未开启时求值报错             |
| `wm.manager`                | `default.nix` | `"aerospace"`    | 窗口管理器，可选 `"aerospace"`、`"omniwm"`（`gui` 及以上）                        |
| `tools.autoinputswitch.app` | `default.nix` | `"typeswitch"`   | 自动切换输入法的软件，可选 `"typeswitch"`、`"inputsourcepro"`（`workstation`）    |
| `dotfiles.liveEdit`         | `home.nix`    | `false`          | 配置文件软链到本地仓库，改完即时生效；远程部署机保持关闭                          |
| `backup.backupPaths`        | `home.nix`    | `[ ]`            | kopia 额外备份的路径（`workstation`）                                             |
| `backup.calendarInterval`   | `home.nix`    | 按 hostname 分布 | kopia 快照时间，`"H:M"` 列表；默认 `2:00` 到 `8:00` 间取两个时刻（`workstation`） |
| `backup.policySyncWhen`     | `home.nix`    | `"5:00"`         | kopia 周日策略同步的时间（`workstation`）                                         |
| `dev.ai.sandbox.enable`     | `home.nix`    | `false`          | 安装 agent 沙箱（`workstation`）                                                  |
| `neovim.minimal`            | `home.nix`    | `false`          | 只装 neovim，不带配置                                                             |

## 新增一台主机

1. 复制同类主机的目录（例如 darwin 桌面机可复制 `hosts/ling/`），修改 `hostname`，并在 `imports` 中指定角色
2. 在 `flake.nix` 的 `hosts` 里照抄一条同类主机的 `mkHost`，改成新目录
3. 若需要 sops 密钥，参考根目录 README「初始化」将新机器公钥加入 secrets 仓库，并在 `default.nix` 中配置 `shelken.secrets.enable = true;`
4. 执行 `git add hosts/<主机>`，运行 `just b <主机>` 验证构建

新增 `hosts/` 目录会改变其他主机的 kopia 备份时段：`mylib.calcUniformSchedule` 按 `hosts/` 下的目录数平均分配时间
