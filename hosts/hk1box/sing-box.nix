{
  config,
  lib,
  pkgs,
  ...
}:
let
  stateDir = "/var/lib/sing-box-sub";
  configFile = "${stateDir}/config.json";
  sing-box = config.services.sing-box.package;
  urlFile = config.sops.secrets.sing-box-sub-url.path;

  update = pkgs.writeShellApplication {
    name = "sing-box-sub-update";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.diffutils
      pkgs.systemd
      sing-box
    ];
    text = ''
      tmp=$(mktemp -p ${stateDir} .config.XXXXXX)
      work=$(mktemp -d)
      trap 'rm -rf "$tmp" "$work"' EXIT

      # URL 带着加密载荷，经 stdin 交给 curl，不出现在进程参数与日志里
      printf 'url = "%s"\n' "$(tr -d '\n' < ${urlFile})" \
        | curl --config - --fail --silent --show-error --location \
            --max-time 120 --retry 3 --retry-delay 10 --output "$tmp"

      # 工作目录指向临时目录，check 不在 stateDir 里留下缓存文件
      sing-box check -D "$work" -c "$tmp"

      if [ -f ${configFile} ] && cmp -s "$tmp" ${configFile}; then
        echo "订阅内容未变化"
        exit 0
      fi

      chgrp sing-box "$tmp"
      chmod 0640 "$tmp"
      mv -f "$tmp" ${configFile}
      echo "订阅已更新，重启 sing-box"
      systemctl restart sing-box.service
    '';
  };
in
{
  config = lib.mkMerge [
    {
      # 不声明 settings：模块此时用 -C /etc/sing-box 读整个目录。
      # 1.14 的上游单元以 sing-box 用户运行，并带 CAP_NET_ADMIN 等能力，tun 与监听 53 都不需要 root
      services.sing-box.enable = lib.mkDefault true;
    }
    (lib.mkIf config.services.sing-box.enable {
      # system 栈的 TCP 经 TUN 回注内核，需在输入链的 conntrack 检查前放行。
      networking.firewall.trustedInterfaces = [ "tun0" ];

      sops.secrets.sing-box-sub-url = { };

      systemd.tmpfiles.rules = [
        "d ${stateDir} 0750 root sing-box -"
        "d /etc/sing-box 0755 root root -"
        "L+ /etc/sing-box/config.json - - - - ${configFile}"
      ];

      # EXTERNAL: HK1 Box 无硬件 RTC，断电重启后时钟从旧值起步，启用上游等待同步单元并设 30s 超时兜底不阻塞无网启动
      systemd.additionalUpstreamSystemUnits = [ "systemd-time-wait-sync.service" ];
      systemd.services.systemd-time-wait-sync = {
        wantedBy = [ "time-sync.target" ];
        serviceConfig.TimeoutStartSec = "30s";
      };

      systemd.services.sing-box = {
        after = [ "time-sync.target" ];
        wants = [ "time-sync.target" ];
        unitConfig.ConditionPathExists = configFile;
      };

      # 只由自己的 timer 触发，不挂到任何 target 上：挂上去的话，激活时会因为它是
      # 「完成即 inactive 的 oneshot」被当成没在运行而再拉一遍，订阅服务恰好不通就让
      # 激活失败、触发 deploy-rs 回滚。这里让激活路径完全没有入口启动它。
      systemd.services.sing-box-sub-update = {
        description = "拉取 sing-box 订阅配置";
        wants = [
          "network-online.target"
          "time-sync.target"
        ];
        after = [
          "network-online.target"
          "time-sync.target"
        ];
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe update;
          PrivateTmp = true;
          ProtectHome = true;
        };
      };

      systemd.timers.sing-box-sub-update = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "1min";
          OnUnitActiveSec = "24h";
          RandomizedDelaySec = "10min";
        };
      };
    })
  ];
}
