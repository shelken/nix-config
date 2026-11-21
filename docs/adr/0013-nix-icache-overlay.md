# 内网镜像缓存（icache）按开关动态叠加，不写死在全局静态配置里

日期: 2026-11-21

内网镜像缓存（icache）只在内网可达且随时可能关闭，直接写进系统静态配置会导致外网环境下载失败或回退缓慢。因此 Darwin 用户侧由 `nix-icache` 提供显式 `on` / `off` 开关，动态写入 Nix、mise、Homebrew 三处覆盖文件；常驻内网的 NixOS 主机通过可选模块 `nix-icache-system` 写入系统 `nix.settings`，远端装机脚本 `anywhere-install` 则独立读取目标 NixOS 主机的 `nix.settings` 写入安装环境。

## 规则

- **Nix 状态文件**：状态等价于 `~/.config/nix/icache.conf` 是否存在，靠用户级 `nix.conf` 的 `!include icache.conf` 生效。被包含文件不存在时 Nix 静默忽略；用户级设置由客户端转发给 daemon，改文件即生效，不必重启 daemon。
- **使用覆盖语义的 `substituters`**：Nix 先按各源 `nix-cache-info` 里的 Priority 排序，同级才按列表顺序试源。icache 原样透传上游 Priority，与原站同级，必须排在原站前面；`extra-substituters` 只追加到末尾，在原站可提供该路径时 icache 不会优先命中。开启时动态读取系统列表并把 icache 拼在最前，不在代码里重复维护列表。
- **关闭 `builders-use-substitutes`**：置为 `true` 时远端 builder 会自己拉取 substitute 输入，碰不到内网 icache；置为 `false` 后本机先经 icache 拉取输入，再推给 builder。
- **mise 规则随开关走**：`nix-icache` 仅改写匹配的 `https://github.com/<owner>/<repo>/releases/download/...` 下载地址（其他工具下载路径不受影响）。由于 mise 对被改写的下载失败不回退原站，该规则只写入 `nix-icache` 开关管理的 `~/.config/mise/conf.d/icache.toml`，不写进 Home Manager 生成的 mise 全局配置。
- **Homebrew 同时写两处**：开启时同时写 `~/.config/homebrew/brew.env` 与 `~/.homebrew/brew.env`，把 `ghcr.io` 的 bottle 与 portable-ruby 经 `HOMEBREW_ARTIFACT_DOMAIN` 指到 `icache/ghcr.io`，并保留 `HOMEBREW_DOCKER_REGISTRY_TOKEN=QQ==` 使回退原站时仍带匿名认证。交互 shell 设了 `XDG_CONFIG_HOME` 读前者，nix-darwin 激活跑 `brew bundle` 时未设它读后者。
- **远端装机（`anywhere-install`）**：显式传入 `--no-use-machine-substituters` 关闭 `nixos-anywhere` 默认启用的 `use-machine-substituters`（默认行为会把本机源追加进 `extra-substituters`，同 Priority 原站可用时 icache 不会优先命中），改为直接从目标 NixOS 主机的 `nix.settings` 求值并写入目标机 root 的 `~/.config/nix/nix.conf`。`--build-on remote` 经 `ssh-ng` 启动的 `nix-daemon` 以 root 运行并读取该文件；安装环境在内存中，重启即消失。大体积稀疏数据不经 `extra-files`（`nixos-anywhere` 的 `tar` 未启用 `--sparse`），使用 `PHASES=disko,install` 装完后手动写入 `/mnt` 再重启。

## 考虑过的替代方案

- **在系统 `nix.conf` 中用 `extra-substituters` 永久挂接 icache**：同 Priority 下排在原站后不会优先命中；外网环境下还会拖慢查询。
- **把 mise 的 GitHub release 镜像规则写进 Home Manager 静态配置**：mise 失败不回退原站，离开内网后命中该规则的工具下载直接报错。

## 后果

- 首次 switch 写入系统 `/etc/nix/nix.custom.conf`（由 Determinate 主 `nix.conf` 经 `!include` 引入）后，daemon 不会自动重读，需要执行一次 `sudo launchctl kickstart -k system/systems.determinate.nix-daemon`，之后 `on` / `off` 即时生效。
- 以 root 运行的 Nix 命令（如 `sudo`、`nixos-rebuild`）不读当前普通用户的 `~/.config/nix/icache.conf`，而是读 root 自己的用户配置与系统列表（`anywhere-install` 写入目标机 root 的用户配置正是利用这一行为）。
