# kube：禁用默认 kubeconfig，集群配置按项目用 KUBECONFIG 指定
{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.kube ];

  flake.modules.homeManager.kube = {
    # 只读空文件：写入会报错而不是被静默丢弃；force 直接接管已存在的文件。
    home.file.".kube/config" = {
      text = "";
      force = true;
    };
  };
}
