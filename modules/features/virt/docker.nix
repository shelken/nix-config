# docker 守护进程与镜像加速
# 可选功能，需要时主机 imports = [ self.modules.nixos.docker ]
# 注意：podman.nix 已在桌面机启用 podman 的 docker 兼容层
{
  flake.modules.nixos.docker.virtualisation.docker = {
    enable = true;
    # start dockerd on boot.
    # This is required for containers which are created with the `--restart=always` flag to work.
    enableOnBoot = true;
    daemon.settings = {
      registry-mirrors = [
        "https://mirror.baidubce.com"
        "https://docker.m.daocloud.io"
      ];
    };
  };
}
