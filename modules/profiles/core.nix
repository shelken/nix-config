# 角色链：core ⊂ tui ⊂ gui ⊂ desktop ⊂ workstation，主机只导入一个角色。
# 包含关系只写在系统侧（darwin/nixos）；homeManager.<角色> 只放本层新增内容，
# 经同名挂接随系统侧进入。flake-parts 不给模块设 key，同一模块导入两次不会去重，
# 所以 HM 侧不能再写 imports 链。
#
# 本文件只声明角色本身：功能由各自的功能文件声明加入（ADR 0004 第 6 条），
# profile 不列任何具体功能。
{
  flake.modules.darwin.core = { };
  flake.modules.nixos.core = { };
  flake.modules.homeManager.core = { };
}
