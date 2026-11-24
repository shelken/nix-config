# 软件配置决策

功能位置与文件形式见 `docs/adr/0004-dendritic-feature-modules.md` 与 `docs/adr/0012-feature-domains-and-file-form.md`（参考 `modules/features/input/autoinputswitch.nix`），引入或调整配置时按序决策：

1. 优先使用 home-manager 现成模块，无现成模块再写自定义文件关联
2. 桌面 GUI 产品不编译，由 nix-darwin 或 nixpkgs 安装，安装包方式须与用户确认
3. 自定义配置文件用 `mylib.mkConfigFile` / `mylib.mkConfigLink`（见 `lib/default.nix`）
4. 本地已有现存配置时先提示用户确认处理策略；会自动写入大量动态配置的软件优先「读取后合并覆盖」
