# deploy-rs 节点定义：hostname 复用 vars/networking.nix 生成的 ssh 别名，不重复声明 IP；
# 激活器按主机类型映射（activate.darwin / activate.nixos），deployLib 见 deployRsLib.nix；
# 激活需要 root，默认 interactiveSudo 部署时输一次密码，免改被控机 sudoers。
{
  deployLib,
  name,
  configuration,
  type,
  system,
  # 透传 deploy-rs 通用参数（remoteBuild、autoRollback 等），作用在 system profile 上
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
