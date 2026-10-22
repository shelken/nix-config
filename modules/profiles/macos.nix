# 所有 macOS 主机共用的基础配置。主机导入 darwin.macos 即获得系统与用户态两部分。
# 尚未迁入 modules/features 的旧模块树在此整体引入，迁出一个功能就从旧树删掉，
# 改在这里的 imports 列出 config.flake.modules.darwin.<功能>。
{
  flake.modules.darwin.macos.imports = [ ../darwin ];
  flake.modules.homeManager.macos.imports = [ ../../home/darwin ];
}
