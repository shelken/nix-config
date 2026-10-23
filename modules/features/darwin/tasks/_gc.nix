# 全设备默认任务：nix 自动垃圾回收（存在即启用）
#
# 为什么不走 nix.gc：nix.gc.automatic 要求 nix.enable=true，与
# Determinate Nix 管理 nix.conf 冲突，故用等价 launchd daemon。
{
  ...
}:
{
  shelken.tasks.nix-gc = {
    when = "3:15";
    user = false;
    script = ''
      exec /nix/var/nix/profiles/default/bin/nix-collect-garbage --delete-older-than 7d
    '';
  };
}
