# 可选功能，需要时主机 imports = [ self.modules.nixos.docker ]
{
  flake.modules.nixos.docker.virtualisation.docker = {
    enable = true;
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
