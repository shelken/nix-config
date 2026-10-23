# Zed 编辑器的 HM 配置：同名挂接到 darwin.zed（dev/zed.nix 的 cask，加入 desktop），配置跟随应用本体
{
  flake.modules.homeManager.zed = import ./_zed-hm.nix;
}
