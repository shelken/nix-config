# singbox-config：把 mac / ios / router 三份 sbtools 配置声明式管起来
#
# 私密值在模板里只以 1Password 引用（`{{ op://… }}`）出现，运行时由 sec-run 填充；
# 生成的 yaml 只落在临时目录，encode 完即删。仓库与 nix store 里都没有明文。
#
# 与 mise.nix 同挂 gui：sbtools 由 mise 提供，填充动作依赖 secrets 功能里的 sec-run
{
  config,
  ...
}:
{
  flake.modules.darwin.gui.imports = [ config.flake.modules.darwin.singbox-config ];
  flake.modules.nixos.gui.imports = [ config.flake.modules.nixos.singbox-config ];

  flake.modules.homeManager.singbox-config.imports = [ ./_singbox-config.nix ];
}
