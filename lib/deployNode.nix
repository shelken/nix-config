{
  deployLib,
  name,
  configuration,
  type,
  system,
  extra ? { },
}:
{
  hostname = name;
  # macOS 的 /tmp 是 /private/tmp 符号链接：deploy-rs 确认 watcher 拿原始路径与
  # FSEvents 规范化后的事件路径做全等比较，永远不匹配，30s 后误判未确认而回滚
  # （上游 master 未修）。指定真实路径使 canary 事件路径一致，保住 magic rollback。
  tempPath = if type == "darwin" then "/private/tmp" else "/tmp";
  profiles.system = {
    user = "root";
    interactiveSudo = true;
    path = deployLib.${system}.activate.${type} configuration;
  }
  // extra;
}
