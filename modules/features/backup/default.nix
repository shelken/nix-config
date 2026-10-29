# 备份实现：kopia（secrets 断言 + sops 模板 + shelken.tasks 定时任务）
# 只在 mio（workstation）开启 → workstation；路径参数保留在 shelken.backup.backupPaths。
# kopia 全部是用户态配置（home.packages / shelken.tasks / sops secrets），
# HM 部分经同名挂接自动随 darwin.backup 进入。
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.backup ];

  flake.modules.homeManager.backup.imports = [ ./_kopia ];
}
