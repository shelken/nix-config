# Secrets 管理

唯一 secrets 仓库 = gopass root store(gitfs + age),sops 密文与 gopass 条目在同一仓库内分区共存,一个 secret 值只有一个家。gopass 负责交互式编辑与自动跨机同步,sops-nix 负责声明式渲染给 Nix 消费方。

## 仓库布局

```text
~/.local/share/gopass/stores/root      # 唯一 secrets 仓库(gopass 默认 store 路径)
├── .age-recipients                    # gopass 条目的收件人(age 公钥, 三台 Mac)
├── .sops.yaml                         # sops 加密规则(同一批公钥)
├── sops/secrets/shelken/default.yaml  # sops 密文, sops-nix 渲染的唯一数据源
├── env/                               # gopass 条目, 人类交互式使用(如 env/ai/OPENAI_API_KEY)
├── rotations/                         # 凭据轮换自动化(沿用旧 secrets.nix 仓库的 bun 工具)
└── (origin)                           # GitHub shelken/secrets, 备份与跨机同步远端
```

- gopass 只索引 `.age` 后缀文件,`sops/` 下的 YAML 对 gopass 完全不可见,两个分区互不干扰
- 同步由 gopass 现有机制全自动:`core.autopush`(写条目即提交推送)+ `core.autosync`(每 30 分钟拉推)
- 代码侧组件:`home/base/core/secrets.nix`(sec-run 注入器)、各 agent 组件(`agentEnvMap` profile 白名单)、`justfile`(secret-edit / secrets-doctor)

## 日常使用

### 编辑 gopass 条目(人类交互域)

```bash
gopass insert env/misc/<KEY>   # 新增, 提交推送全自动
gopass edit env/ai/OPENAI_API_KEY
gopass show -o env/ai/OPENAI_API_KEY   # 单值取用(输出到 stdout, 自行接住)
```

### 编辑 sops 密文(Nix 消费域)

```bash
just secret-edit                                    # 默认打开 sops/secrets/shelken/default.yaml
just secret-edit sops/secrets/shelken/<file>.yaml   # 指定其它密文文件
```

编辑保存后自动 `git add` + commit + `gopass sync`(gitfs 的 sync 不提交非 `.age` 文件的变更, 提交动作收敛在此)

新增密文文件后需先 `git add`,否则对构建不可见:`git -C <store> add sops/...`

### 让 Nix 侧生效

```bash
just hm-dev        # 本地秒级生效: 直接读 store 现状, 不需要 push
just upp secrets   # 推进 flake.lock 中 secrets 输入(常规 rebuild / 其它机器消费远端时)
```

- 迁移前旧链路回退:`LOCAL_SECRETS_DIR=$HOME/code/MyRepo/nix/secrets.nix just hm-dev`

### 体检

```bash
just secrets-doctor   # 只读: recipients 一致性 / 未提交内容 / remote 配置
```

两份收件人列表(`.age-recipients` 与 `.sops.yaml`)由不同工具消费,无法合并;新增或移除机器后必须两侧同时更新,doctor 负责发现漂移

## agent/LLM 使用

`sec-run` 是唯一注入入口,profile 白名单由各 agent 组件声明在自身的 `shelken.secrets.agentEnvMap.<profile>`(如 `home/base/gui/dev/ai/pi.nix`),经 Nix 期固化,运行期零解密操作

```bash
sec-run --list                    # 列出 human 与各 profile 可见变量名(不含值)
pi                                # alias 已接好: sec-run --agent=pi
sec-run --agent=omp -- gh pr list # 直接指定 profile
sec-run --agent=pi --ttl 2h -- pi # 显式续期授权
```

- agent 模式只注入该 profile 白名单内的变量,并主动清除白名单外可能从父 shell 继承的已声明 secret 变量;永不读取 `~/.specific.zsh`
- 授权默认 24h,过期后启动失败并提示续期;续期动作即审计点
- 审计日志只记变量名与命令,不含值:`~/.local/state/sec-run/audit.log`

## 一次性迁移(需自行执行, 按序)

> ⚠️ 本 PR 代码已移除 `sec-run` 对 `~/.specific.zsh` 的加载与 `sec-env` 命令。必须先完成下面第 6 步(值导入),再执行第 9 步 rebuild,否则这些变量会从环境消失

1. 备份

   ```bash
   cp -a $HOME/code/MyRepo/nix/secrets.nix $HOME/backup/secrets-legacy-$(date +%F)
   cp -a $HOME/.local/share/gopass/stores/root $HOME/backup/gopass-store-$(date +%F)
   ```

2. 旧仓库内容拷入 store(未提交状态)

   ```bash
   cd $HOME/code/MyRepo/nix/secrets.nix
   cp -R sops .sops.yaml rotations raycast README.md justfile ~/.local/share/gopass/stores/root/
   gopass ls | grep -v '^env' || echo OK   # 验证: sops YAML 不出现在 gopass 条目中
   ```

3. store 内提交一次

   ```bash
   git -C ~/.local/share/gopass/stores/root add -A
   git -C ~/.local/share/gopass/stores/root commit -m "absorb legacy sops repo"
   ```

4. 接上远端 `shelken/secrets`(空私有仓库已建好)并推送 store

   ```bash
   git -C ~/.local/share/gopass/stores/root remote add origin git@github.com:shelken/secrets.git
   git -C ~/.local/share/gopass/stores/root push -u origin main
   git ls-remote origin refs/heads/main   # 验证: 与 store HEAD 一致
   ```

5. 切换 flake input 到新仓库(改 `flake.nix` 一行)

   ```diff
       secrets = {
   -     url = "git+https://github.com/shelken/secrets.nix.git?shallow=1";
   +     url = "git+https://github.com/shelken/secrets.git?shallow=1";
         flake = false;
       };
   ```

   本地秒级生效仍走 `just hm-dev`(override 直读 store, 不依赖此 url);不切 url 则远端链路拉不到新内容

6. `~/.specific.zsh` 值导入(在 rebuild 之前!)

   ```bash
   grep -E '^\s*(export\s+)?[A-Za-z_][A-Za-z0-9_]*=' ~/.specific.zsh \
     | sed -E 's/^\s*(export\s+)?//; s/=.*//' | sort -u   # 列出变量名
   gopass insert env/misc/<KEY>                            # 逐条录入(值不在命令行出现)
   ```

7. gopass 解锁体验(两行配置, 与 1Password 常解锁体验对齐)

   ```bash
   gopass config age.agent-timeout 900   # 解锁缓存 15 分钟后自动锁定(当前 0 = 永不过期)
   gopass config age.usekeychain true    # 口令进 macOS Keychain
   ```

8. rebuild 应用本 PR(hm 或 bd),然后验证

   ```bash
   just secrets-doctor       # 三项全 ✅
   sec-run --list            # 名单符合预期
   sec-run env >/dev/null    # 人类模式注入正常
   pi --version              # agent 模式首次执行会写入 24h 授权
   ```

   此后删除逃生舱:`shred -u ~/.specific.zsh`

9. 收尾: 旧 clone 保留两周无回退需求后删除;`rotations` 里的轮换向导照旧在 store 目录下运行 `just rotate`

## 新 Mac onboarding

同一把 age 身份(ssh-to-age 派生)同时服务 `.sops.yaml` 与 `.age-recipients`,两处公钥集合必须一致

```bash
# 1. sops 侧身份
nix run nixpkgs#ssh-to-age -- < ~/.ssh/id_ed25519.pub            # 公钥交由旧机器录入两侧
nix run nixpkgs#ssh-to-age -- -private-key -i ~/.ssh/id_ed25519 \
  > ~/.config/sops/age/keys.txt

# 2. 旧机器上: 两侧收件人 + 重加密
gopass recipients add age1<新机公钥>
sops $HOME/.local/share/gopass/stores/root/sops/secrets/shelken/default.yaml   # 打开即按新 .sops.yaml 重加密, 保存即可
# 或者: sops updatekeys <密文文件>

# 3. 新机器 clone + 导入身份
gopass clone git@github.com:shelken/secrets.git
gopass age identities add "$(cat ~/.config/sops/age/keys.txt)"
gopass recipients ack && gopass sync
gopass show -o env/ai/OPENAI_API_KEY >/dev/null && echo OK   # 验证: 能解密即完成
```

## flake input 的两种形态

迁移第 5 步已把 `flake.nix` 的 `secrets` 输入切到新仓库 `git+https://github.com/shelken/secrets.git`。另一种形态是直接指本地 store:

```nix
secrets = {
  url = "path:" + /Users/shelken/.local/share/gopass/stores/root;
  flake = false;
};
```

- 问题 -> 代价: path 输入被 `narHash` 锁定,store 有未提交修改时普通构建静默使用旧内容且无警告 -> 日常一律 `just hm-dev`(永远取现状),`nix flake metadata` 可随时核对输入的 `narHash` 是否落后

## 回退

- 代码回退: revert 本 PR;`sec-run`/`sec-env` 恢复原行为
- 数据回退: store 与旧仓库互相独立,第 1 步的备份 + 旧 clone 可完整重建任一侧
- 链路回退: `LOCAL_SECRETS_DIR=$HOME/code/MyRepo/nix/secrets.nix just hm-dev` 继续用旧 clone

## 安全边界(诚实声明)

- agent 与人类同 OS 用户,任何 wrapper/白名单都挡不住有任意 shell 执行权的进程直接读渲染文件;真正的兜底是 profile 只放最小权限短周期凭据 + `rotations` 轮换
- 高敏感凭据建议走 fine-grained token(如 GitHub fine-grained PAT),泄漏即平台侧吊销
- sops 渲染文件 0500 落盘,依赖 FileVault 全盘加密兜底
