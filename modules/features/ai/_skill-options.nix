# shelken.dev.ai.skills 的接口选项：声明在 core，任何功能都能登记自带的 skill（ADR 0004、0008）；
# 部署实现在 skill.nix，只在导入 ai 的主机上生效
{ lib, ... }:
{
  options.shelken.dev.ai.skills = lib.mkOption {
    type = lib.types.listOf lib.types.path;
    default = [ ];
    description = ''
      功能目录自带的本地 skill：含 SKILL.md 的目录，写路径字面量（如 ./iphone-use-best-practice）。
      目录名即 skill 名，与 skills/ 下的本地 skill、外部 skill 不能重名。
    '';
  };
}
