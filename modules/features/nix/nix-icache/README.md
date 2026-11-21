# nix-icache

内网镜像缓存（icache）只在内网可达且随时可能关闭，写进全局静态配置会让外网环境下载失败或回退缓慢。Darwin 用户侧由 `nix-icache` 提供 `on` 与 `off` 开关，动态管理 Nix、mise、Homebrew 三处覆盖文件。常驻内网的 NixOS 主机经可选模块 `nix-icache-system` 写入系统 `nix.settings`，远端装机脚本 `anywhere-install` 从目标主机配置生成安装环境的 `nix.conf`

## 设计要点

- Nix 开关状态由 `~/.config/nix/icache.conf` 是否存在决定，用户级 `nix.conf` 经 `!include icache.conf` 引入，文件不存在时 Nix 静默忽略，改文件即时生效
- `substituters` 采用覆盖语义。icache 透传上游 Priority，与原站同级，必须排在原站之前才能优先命中。开启时脚本动态读取系统源列表并把 icache 拼在最前，不用 `extra-substituters` 追加到末尾
- 开启 icache 时用户级覆盖文件将 `builders-use-substitutes` 覆写为 `false`，本机先经 icache 拉取输入再推给远端 builder。系统层 `nix-settings.nix` 仍保持 `true`
- mise 镜像规则只写入 `~/.config/mise/conf.d/icache.toml`，不写进 Home Manager 静态配置，因为 mise 在改写后的下载地址失败时不会回退原站。规则只改写 `https://github.com/<owner>/<repo>/releases/download/...`
- Homebrew 开启时同时写 `~/.config/homebrew/brew.env` 与 `~/.homebrew/brew.env`，因为交互 shell 读取 `XDG_CONFIG_HOME`，而 `nix-darwin` 激活执行 `brew bundle` 时未设该变量。文件保留匿名 `HOMEBREW_DOCKER_REGISTRY_TOKEN=QQ==` 供回退官方源使用
- 远端装机传入 `--no-use-machine-substituters`，避免 `nixos-anywhere` 把本机源追加进 `extra-substituters`，改为求值目标主机的 `nix.settings` 写入目标机 root 的 `~/.config/nix/nix.conf`。大体积稀疏数据不经 `--extra-files`，因为 `nixos-anywhere` 的 `tar` 未启用 `--sparse`，在 `PHASES=disko,install` 后手动写入 `/mnt`

## 注意事项

- 首次 switch 写入 `/etc/nix/nix.custom.conf` 后，执行 `sudo launchctl kickstart -k system/systems.determinate.nix-daemon` 使 daemon 重读，之后 `on` 与 `off` 即时生效
- 以 root 运行的 Nix 命令不读取普通用户的 `icache.conf`，读取 root 自己的用户配置与系统列表
