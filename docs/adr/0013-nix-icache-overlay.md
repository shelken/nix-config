# 内网镜像缓存（icache）动态叠加，不写死在全局静态配置

日期: 2026-11-21

icache 只在内网可达且随时可能关闭，写进系统静态配置会让外网环境下载失败或回退缓慢。Darwin 用户侧由 `nix-icache` 提供显式 `on` / `off` 开关，动态写入 Nix、mise、Homebrew 三处覆盖文件；常驻内网的 NixOS 主机经可选模块 `nix-icache-system` 写入系统 `nix.settings`，远端装机脚本 `anywhere-install` 独立读取目标主机的 `nix.settings` 写入安装环境

## 规则

- 用户级开关状态等价于 `~/.config/nix/icache.conf` 是否存在，靠用户级 `nix.conf` 的 `!include icache.conf` 生效，改文件即生效，不必重启 daemon
- `substituters` MUST 用覆盖语义：Nix 先按各源 `nix-cache-info` 的 Priority 排序，icache 原样透传上游 Priority 与原站同级，MUST 排在原站前面；开启时 MUST 动态读取系统列表把 icache 拼在最前，MUST NOT 在代码里重复维护列表；`extra-substituters` 只追加到末尾，MUST NOT 用来挂 icache
- MUST 关闭 `builders-use-substituters`：置 `true` 时远端 builder 自己拉输入碰不到 icache，置 `false` 后本机先经 icache 拉取再推给 builder
- mise 规则 MUST 只写入开关管理的 `~/.config/mise/conf.d/icache.toml`，MUST NOT 进 Home Manager 生成的 mise 全局配置（mise 对被改写的下载失败不回退原站）；MUST 只改写 `https://github.com/<owner>/<repo>/releases/download/...` 下载地址，其他下载路径 MUST NOT 受影响
- Homebrew 开启时 MUST 同时写 `~/.config/homebrew/brew.env` 与 `~/.homebrew/brew.env`（交互 shell 设了 `XDG_CONFIG_HOME` 读前者，激活跑 `brew bundle` 时未设读后者），把 `ghcr.io` 的 bottle 与 portable-ruby 指到 `icache/ghcr.io`，保留匿名认证 token
- 远端装机 MUST 显式传 `--no-use-machine-substituters`（默认行为会把本机源追加进 `extra-substituters`，icache 不会优先命中），MUST 从目标 NixOS 主机的 `nix.settings` 求值并写入目标机 root 的 `~/.config/nix/nix.conf`；大体积稀疏数据 MUST NOT 经 `--extra-files`（`nixos-anywhere` 的 tar 未启用 `--sparse`），用 `PHASES=disko,install` 装完后手动写入 `/mnt` 再重启

## 考虑过的替代方案

- 系统 `nix.conf` 用 `extra-substituters` 永久挂接：同 Priority 排在原站后不会优先命中，外网环境还拖慢查询
- mise 镜像规则写进 Home Manager 静态配置：离开内网后命中该规则的工具下载直接报错

## 后果

- 首次 switch 写入 `/etc/nix/nix.custom.conf` 后 daemon 不会自动重读，MUST 手动执行一次 `sudo launchctl kickstart -k system/systems.determinate.nix-daemon`，之后 `on` / `off` 即时生效
- root 运行的 Nix 命令（`sudo`、`nixos-rebuild`）不读普通用户的 `icache.conf`，读 root 自己的用户配置与系统列表
