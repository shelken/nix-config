# 共享工具登记表：第一批 Nix 条目（rg/fd/jq/gh/node/python3/uv，ADR 0003）
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
  };
}
