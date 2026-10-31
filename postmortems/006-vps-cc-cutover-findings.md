# vps-cc 切换后发现的问题：自动 IPv6 回包、日志驱动、重建与激活器编译

**日期**: 2026-10-31
**影响**: hysteria2 经 IPv6 的 UDP 握手超时（TCP 不受影响）；compose 部署报错，两处服务的日志选项被临时注释；每次部署要重建一串小派生并拷贝约 2 GiB；本机磁盘 95% 已用
**发现人**: 切换后用户的客户端测试与抓包（IPv6），部署日志（其余）；各自的分析见对应 issue

## 问题

- 演练在 Lima 的 qemu 里做，暴露不了真机上服务商路由器的通告、新旧系统 docker 日志驱动的差别，也暴露不了本机构建链路的真实代价
- 切换后发现四件事。前两件是新旧系统默认值不同，后两件是构建链路

## 现象

1. 独立客户端经固定 IPv6 连 hysteria2 握手超时，服务端回环握手成功。抓包看到服务端回包的源地址不是客户端请求的固定地址，而是网卡上自动生成的地址。`accept_ra` 为 1，网卡在三个前缀上各多一个自动地址，排在三个静态地址之前。`ip -6 route get` 对同网段和公网目的地都选自动地址当源地址
2. `task compose:deploy:vps` 报 `unknown log opt 'max-size' for journald log driver`，16 个容器的日志驱动都是 `journald`
3. 步骤 0 构建的系统与实际部署的系统不是同一个。部署时出现 57 个构建、232 个路径复制（2.0 GiB）、473 MiB 下载
4. 部署之后本机可用空间少几个 GB。`/nix/store` 只有 29 GB，卷已用 434 / 461 GB，构建机镜像 16.3 / 20 GiB

## 根因

1. 真机的路由器会发路由通告，内核默认接受并生成自动地址，它们排在静态地址之前，选源时胜出。监听通配地址的 UDP 服务回包由内核选源，TCP 沿用连接的本地地址所以不受影响。演练里没有通告，005 里为 `accept_ra` 设的 `all`、`default` 又无效，被直接去掉，没有换成对网卡的设置。hysteria2 没有按目的地址回包的具体原因（obfs 包装丢掉了地址信息）是推断，没有验证
2. NixOS 的 `virtualisation.docker.logDriver` 默认是 `journald`，旧 Ubuntu 是 `json-file`，`journald` 不接受 `max-size`、`max-file`。fluent-bit 采集的是 caddy 的访问日志文件，不依赖日志驱动
3. flake 里引用仓库内的文件，其字符串上下文指向整个仓库源码的 store 路径，所以任一已跟踪文件的改动，都会改变所有引用了仓库文件的派生（home-manager 文件、`hm-putter.json`，一路到 toplevel）。构建之后我改过 `justfile`。232 个路径、2.0 GiB 的拷贝方向没有逐项确认
4. deploy-rs 的激活器默认从 flake 源码编译。`deploy-rs-1.0.0` 在 `cache.nixos.org`、`nix-community.cachix.org`、`cache.garnix.io` 都没有。去掉 `follows`、用它自己锁定的 nixpkgs，同样没有。nixpkgs 自带的 `deploy-rs` 在 `cache.nixos.org` 有，`x86_64-linux` 与 `aarch64-darwin` 都有。部署产物没有 GC 根，每周 GC 会删掉；构建机里没有 GC，镜像是稀疏文件，只增不缩。「每次部署少几 GB」是这两处叠加，是推断，没有做部署前后的对比

## 修复

- IPv6：`hosts/vps/vps-cc/default.nix` 对网卡设 `accept_ra = 0`、`autoconf = 0`。已部署到 vps-cc，已有的自动地址手动清掉后，内核对同网段和公网都改选固定地址。两条带过期时间的前缀路由残留，重启后是否重新学到没有验证。客户端重测待做（nix-config #182）
- 日志驱动：本机临时注释了两处 `logging.options`，未提交。倾向沿用 `journald` 并删掉这两段，备选是在 nix-config 把驱动改回 `json-file`（home-ops #1728）
- 重建：流程上构建之后不再改已跟踪文件，或接受重建；结构上收窄 home-manager 对仓库根路径的引用（nix-config #181）
- 激活器：按 deploy-rs README 的 overlay 改用 nixpkgs 的缓存包。工作区已改，`--dry-run` 验证构建清单里没有 Rust 相关构建，未部署（nix-config #184）
- 磁盘：未处理（nix-config #185）

## 预防

- 接管后用 `ip -6 addr` 与 `ip -6 route get <公网 IPv6>` 对比新旧机器的地址与选源，不要只看地址列表。去掉一个「没生效的设置」时，要换成能生效的写法，不能只删
- 接管前对比 `docker info` 的日志驱动与 compose 里的 `logging`
- 构建之后、部署之前不要再改已跟踪文件。想知道会不会重建，用 `nix build <路径> --dry-run`
- 判断一个工具会不会编译：先用 `nix path-info --store https://cache.nixos.org <路径>` 查 cache。`--dry-run` 只列要构建与要下载的内容，不下载
- 本机 `df` 看到空间下降，先分清是 `/nix/store`、构建机镜像还是别的目录。`/nix/store` 只占一小部分
