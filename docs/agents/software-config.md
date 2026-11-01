# 软件配置决策

放置位置：一个软件一个功能，放在 `modules/features/<分类>/<名>`，系统侧（brew、launchd、defaults）与 Home Manager 部分写在同一处。功能加入哪个角色、何时用选项而不是导入，按 `docs/adr/0004-dendritic-feature-modules.md`「规则」里的「差异落点」决定；参考样本 `modules/features/tools/autoinputswitch/`

引入或管理一个新软件的配置时，按此顺序决策：

1. 优先使用 home-manager 现成模块；无现成模块时再编写自定义文件关联
2. 桌面端 GUI 产品遵循不编译原则，通过 nix-darwin 或 nixpkgs（如 brew cask）安装；安装包方式需与用户确认
3. home-manager 缺少现成配置时，使用 `mylib.mkConfigFile config ./x` 或 `mylib.mkConfigLink config ./x`（路径字面量，相对当前功能文件）；开发机开启 `shelken.dotfiles.liveEdit` 可实现即时生效，远程部署机自动采用 Nix Store 路径保障自包含与原子回滚
4. 本地已有现存配置时，需先提示用户并确认处理策略
5. 软件若会自动写入大量动态配置，优先采用「读取后合并覆盖」，默认不进行全量静态声明管理

`liveEdit = false` 时，辅助函数返回 `modules/` 快照中的同一相对路径。快照保留 `modules/` 内的完整目录结构，脚本可读取同目录文件，配置可引用其他功能目录；`modules/` 以外的仓库文件（README、justfile、hosts 等）变化不会改变配置来源。传入路径必须位于 `modules/` 内。不要通过字符串插值仓库根路径来构造配置来源，否则整个仓库会进入其依赖。
