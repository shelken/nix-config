{
  flake.modules.nixos.docker.virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    daemon.settings = {
      registry-mirrors = [
        "https://mirror.baidubce.com"
        "https://docker.m.daocloud.io"
      ];
    };
  };
}
