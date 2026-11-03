{
  config,
  lib,
  pkgs,
  ...
}:
#############################################################
#
#  sing-box：配置从订阅服务拉取，与 Mac / iOS 同一条链路
#
#  订阅 URL 由 Mac 上 `sbtools encode -c <路由器用的 yaml>` 生成，yaml 里
#  template_url 指向 proxy 仓库的 template-router.json，设备白名单、clash API 的 secret
#  都写在 overlay 里，随载荷加密，不出现在任何仓库的明文中。
#  URL 本身等同凭据（能换出完整节点配置），放在 secrets 仓库的 sops 文件里。
#
#  拉取：开机一次 + 每 6 小时一次；先 `sing-box check`，内容有变化才原子替换并重启。
#  拉取或校验失败时保留上一份，所以订阅服务暂时不可用也能正常开机。
#
#    /var/lib/sing-box-sub/config.json   ← 最近一次通过校验的配置（root:sing-box 0640）
#    /etc/sing-box/config.json           → 软链到上面；nixpkgs 模块不写 settings 时用 -C /etc/sing-box
#
#############################################################
let
  stateDir = "/var/lib/sing-box-sub";
  configFile = "${stateDir}/config.json";
  sing-box = config.services.sing-box.package;
  # 试机镜像（./image.nix）清空了 sops.secrets，但被关掉的服务的定义仍会被求值，
  # 所以这里给一个缺省路径，免得取不到属性；正式系统里始终用 sops 给出的路径
  urlFile =
    (config.sops.secrets.sing-box-sub-url or { path = "/run/secrets/sing-box-sub-url"; }).path;

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
      # 同一文件系统内 mv 是原子替换，sing-box 不会读到半份文件
      mv -f "$tmp" ${configFile}
      echo "订阅已更新，重启 sing-box"
      systemctl restart sing-box.service
    '';
  };
in
{
  # 不声明 settings：模块此时用 -C /etc/sing-box 读整个目录。
  # 1.14 的上游单元以 sing-box 用户运行，并带 CAP_NET_ADMIN 等能力，tun 与监听 53 都不需要 root
  services.sing-box.enable = true;

  # 订阅 URL：secrets 仓库 sops/secrets/hosts/hk1box.yaml 的 sing-box-sub-url 键
  sops.secrets.sing-box-sub-url = { };

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 root sing-box -"
    "d /etc/sing-box 0755 root root -"
    "L+ /etc/sing-box/config.json - - - - ${configFile}"
  ];

  # 首次开机还没有配置时不启动，等拉取成功后由拉取脚本拉起，避免反复失败重启
  systemd.services.sing-box.unitConfig.ConditionPathExists = configFile;

  systemd.services.sing-box-sub-update = {
    description = "拉取 sing-box 订阅配置";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    # 开机拉一次；不阻塞开机（multi-user 只 Wants 它）
    wantedBy = [ "multi-user.target" ];
    # 部署时不跑它：订阅服务恰好不通会让激活报失败，进而触发 deploy-rs 回滚。
    # 换了订阅 URL 后手动 `systemctl start sing-box-sub-update`，或等下一次定时
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
      OnBootSec = "6h";
      OnUnitActiveSec = "6h";
      RandomizedDelaySec = "10min";
    };
  };
}
