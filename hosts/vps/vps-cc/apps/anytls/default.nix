{ config, ... }:
let
  # 证书目录由入口脚本生成一次（sing-box 自签 keypair），之后复用
  certDir = "/data/docker/sing-box/cert";
in
#############################################################
#
#  anytls：sing-box 的 anytls 入站，用宿主机网络（5444/tcp）
#
#  继续用镜像：入口脚本负责「证书不存在就自签一份」，证书目录在宿主机上，
#  nixpkgs 的 sing-box module 以专用用户 + 单位硬化运行，没有放开这些宿主机路径的开关。
#  口令与自签证书的 SAN 由 sops 渲染，配置与入口脚本都随服务目录挂进容器。
#
#############################################################
{
  sops.secrets = {
    "anytls/password" = { };
    "anytls/server-name" = { };
  };

  sops.templates."anytls.env" = {
    content = ''
      SERVER_NAME=${config.sops.placeholder."anytls/server-name"}
    '';
    restartUnits = [ "docker-anytls.service" ];
  };

  sops.templates."anytls-config.json" = {
    content = ''
      {
        "log": {
          "level": "warn",
          "timestamp": true
        },
        "dns": {
          "servers": [
            {
              "type": "udp",
              "tag": "local",
              "server": "127.0.0.1",
              "server_port": 53
            }
          ],
          "strategy": "prefer_ipv4"
        },
        "inbounds": [
          {
            "type": "anytls",
            "tag": "anytls-in",
            "listen": "::",
            "listen_port": 5444,
            "users": [
              {
                "name": "sammy",
                "password": "${config.sops.placeholder."anytls/password"}"
              }
            ],
            "tls": {
              "enabled": true,
              "server_name": "${config.sops.placeholder."anytls/server-name"}",
              "certificate_path": "/etc/sing-box/cert/cert.pem",
              "key_path": "/etc/sing-box/cert/key.pem"
            }
          }
        ],
        "outbounds": [
          {
            "type": "direct",
            "tag": "direct",
            "domain_resolver": "local"
          }
        ],
        "route": {
          "rules": [
            {
              "action": "sniff"
            },
            {
              "protocol": "bittorrent",
              "action": "reject"
            }
          ],
          "final": "direct"
        }
      }
    '';
    restartUnits = [ "docker-anytls.service" ];
  };

  virtualisation.oci-containers.containers.anytls = {
    image = "ghcr.io/sagernet/sing-box:v1.14.2@sha256:afbffd294c5eb3519cc7b4587299ef189bb0a2ca2f667cb6301fdb6b9bce9558";
    autoStart = true;
    entrypoint = "/entrypoint.sh";
    environmentFiles = [ config.sops.templates."anytls.env".path ];
    volumes = [
      "${config.sops.templates."anytls-config.json".path}:/etc/sing-box/config.json:ro"
      "${./entrypoint.sh}:/entrypoint.sh:ro"
      "${certDir}:/etc/sing-box/cert"
    ];
    extraOptions = [ "--network=host" ];
    labels = {
      "homepage.group" = "VPS";
      "homepage.name" = "anytls";
      "homepage.icon" = "https://avatars.githubusercontent.com/u/83217677";
      "homepage.description" = "AnyTLS";
    };
  };
}
