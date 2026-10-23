# 角色链：core ⊂ tui ⊂ gui ⊂ desktop ⊂ workstation，主机只导入一个角色。
# 包含关系只写在系统侧（darwin/nixos）；homeManager.<角色> 只放本层新增内容，
# 经同名挂接随系统侧进入。flake-parts 不给模块设 key，同一模块导入两次不会去重，
# 所以 HM 侧不能再写 imports 链。
#
# 旧目录（modules/base、home/base/*）已迁为 features/ 下的独立功能，
# 由各功能文件自己声明加入哪一层。
{ config, ... }:
{
  flake.modules.darwin.core = {
    imports = [
      config.flake.modules.darwin.overlays
      config.flake.modules.darwin.system-packages
      config.flake.modules.darwin.secrets
    ];
  };

  flake.modules.nixos.core = {
    imports = [
      ../nixos/base
      config.flake.modules.nixos.overlays
      config.flake.modules.nixos.nix-settings
      config.flake.modules.nixos.system-packages
      config.flake.modules.nixos.user-account
      config.flake.modules.nixos.secrets
      config.flake.modules.nixos.fonts
    ];
    home-manager.sharedModules = [ ../../home/linux/base ];
  };

  flake.modules.homeManager.core.imports = [
    config.flake.modules.homeManager.home-base
    config.flake.modules.homeManager.zsh
    config.flake.modules.homeManager.git
    config.flake.modules.homeManager.ssh
    config.flake.modules.homeManager.starship
    config.flake.modules.homeManager.catppuccin-theme
    config.flake.modules.homeManager.rclone-conf
    config.flake.modules.homeManager.btop
    config.flake.modules.homeManager.core-cli
    config.flake.modules.homeManager.fastfetch
    config.flake.modules.homeManager.yazi
    config.flake.modules.homeManager.dev-options
    config.flake.modules.homeManager.infisical
  ];
}
