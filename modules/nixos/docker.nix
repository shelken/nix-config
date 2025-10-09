{ ... }:
{
  virtualisation.docker = {
    enable = true;
    # start dockerd on boot.
    # This is required for containers which are created with the `--restart=always` flag to work.
    enableOnBoot = true;
    daemon.settings = {
      #proxies = {
      #  "http-proxy" = "http://192.168.6.1:7890";
      #  "https-proxy" = "http://192.168.6.1:7890";
      #};
      registry-mirrors = [
        # "https://hub-mirror.c.163.com"
        "https://mirror.baidubce.com"
        "https://docker.m.daocloud.io"
        # "https://docker.nju.edu.cn"
        # "https://docker.mirrors.sjtug.sjtu.edu.cn"
      ];
    };
    #extraOptions = "--http-proxy 'http://192.168.6.1:7890' --https-proxy 'http://192.168.6.1:7890'";
  };
}
