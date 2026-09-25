# deploy-rs 节点定义：hostname 复用 vars/networking.nix 生成的 ssh 别名，不重复声明 IP；
# 激活器按主机类型映射（activate.darwin / activate.nixos）；
# 激活需要 root，默认 interactiveSudo 部署时输一次密码，免改被控机 sudoers。
{
  deploy-rs,
  name,
  configuration,
  type,
  system,
  # 透传 deploy-rs 通用参数（remoteBuild、autoRollback 等），作用在 system profile 上
  extra ? { },
}:
{
  hostname = name;
  profiles.system = {
    user = "root";
    interactiveSudo = true;
    path = deploy-rs.lib.${system}.activate.${type} configuration;
  }
  // extra;
}
