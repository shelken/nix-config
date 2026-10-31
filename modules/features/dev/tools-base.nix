# 共享工具登记表：dev 侧条目（Nix 基础工具与运行时 + mise 工具，ADR 0003）
# 登记表接口与宿主生成器在 dev/tools.nix；此处与 ai 侧 mise 条目（ai/tools.nix）共用一张表。
{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.dev ];

  flake.modules.homeManager.dev.shelken.dev.tools = {
    # Nix 基础工具与运行时
    rg.package = "ripgrep";
    fd = { };
    jq = { };
    gh = { };
    node.package = "nodejs";
    python3 = { };
    uv = { };

    # mise 共享工具：项目 git hook 运行器（各项目不再在 mise.toml 里声明本体）
    prek.mise = "0.5.9";
  };
}
