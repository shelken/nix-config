# 关闭 Determinate 的 external-builders，让 Linux 构建走 darwin.nix 里的 ssh builder
#
# 为什么在用户级：Determinate 写在 /etc/nix/nix.conf 的 external-builders 排在
# `!include nix.custom.conf` 之后，系统层的 nix.custom.conf 覆盖不了；
# trusted-users 的用户级设置会由 nix 客户端传给 daemon。
# 上游 #730 修复后，删掉本功能的导入，Determinate 的 builder 自动恢复。
{
  flake.modules.homeManager.linux-builder = {
    home.file.".config/nix/nix.conf".text = ''
      external-builders = []
    '';
  };
}
