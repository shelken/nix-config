# nix-icache

内网镜像缓存（icache）仅内网可达，写死在全局配置会导致外网失败或回退慢。Darwin 由 `nix-icache on/off` 动态管理 Nix、mise、Homebrew 覆盖文件；常驻内网的 NixOS 主机经 `nix-icache-system` 写入系统 `nix.settings`，`anywhere-install` 按目标主机配置生成安装环境 `nix.conf`

## 设计要点与注意事项

- `substituters` 用覆盖语义把 icache 拼在系统源最前（icache 透传上游 Priority，用 `extra-substituters` 追加到末尾无法优先命中）
- 开启时将用户级 `builders-use-substitutes` 覆写为 `false`（系统层 `nix-settings.nix` 仍为 `true`），让本机先经 icache 拉取再推远端 builder
- mise 规则只写 `~/.config/mise/conf.d/icache.toml`（不写进 HM 静态配置），因 mise 改写后下载失败不回退原站
- Homebrew 同时写 `~/.config/homebrew/brew.env` 与 `~/.homebrew/brew.env`，因 `nix-darwin` 跑 `brew bundle` 时未设 `XDG_CONFIG_HOME`
- 远端装机传 `--no-use-machine-substituters`，防止 `nixos-anywhere` 把本机源追加进 `extra-substituters`，改为求值目标主机配置写入目标机 root 的 `~/.config/nix/nix.conf`
- 首次 switch 写入 `/etc/nix/nix.custom.conf` 后需执行 `sudo launchctl kickstart -k system/systems.determinate.nix-daemon` 才生效；以 root 运行的 Nix 命令不读普通用户的 `icache.conf`
