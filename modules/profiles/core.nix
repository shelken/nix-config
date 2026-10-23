# 角色链：core ⊂ tui ⊂ gui ⊂ desktop ⊂ workstation，主机只导入一个角色。
# 包含关系只写在系统侧（darwin/nixos）；homeManager.<角色> 只放本层新增内容，
# 经同名挂接随系统侧进入。flake-parts 不给模块设 key，同一模块导入两次不会去重，
# 所以 HM 侧不能再写 imports 链。
#
# 迁移期间各层先整体引入旧模块树，迁出一个功能就从旧树删掉，
# 改由功能文件自己声明加入哪一层（见 features/tools/autoinputswitch/darwin.nix）。
{
  # [临时] W2Base 的 modules/base（fonts 选项声明）未合入前求值需要；提交前移除
  flake.modules.darwin.core.imports = [ ../base ];

  flake.modules.nixos.core = {
    imports = [
      ../nixos/base
      ../base
    ];
    home-manager.sharedModules = [ ../../home/linux/base ];
  };

  flake.modules.homeManager.core.imports = [
    ../../home/base/core
    ../../home/base/home.nix
  ];
}
