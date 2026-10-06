# 软件配置决策

引入或管理一个新软件的配置时，按此顺序决策：

1. 优先 home-manager 现成模块；没有才自己写文件关联
2. 桌面端 GUI 产品遵循不编译原则，用 nix-darwin/nixpkgs 安装（brew cask 等）；安装包的方式必须与用户确认
3. home-manager 没有现成配置时，使用 `mylib.mkConfigFile` / `mylib.mkConfigLink`；开发机开启 `shelken.dotfiles.liveEdit` 即可即时生效，远程部署机自动使用纯 Nix Store 路径保证自包含与原子回滚
4. 本地已有配置时，告知用户，让用户决定如何对待存在的配置
5. 软件会自动生成大量默认配置到配置文件时，优先「读取后合并覆盖」，默认不做全量声明式管理
