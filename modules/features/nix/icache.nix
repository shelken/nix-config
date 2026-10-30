# icache 开关：在家走内网镜像，出门关掉，避免每次 substituter 查询白等连接超时
#
# 状态 = ~/.config/nix/icache.conf 是否存在，靠用户级 nix.conf 的 `!include icache.conf` 生效
# （被包含文件不存在时 nix 静默忽略；用户级设置由客户端转发给 daemon，改文件即生效，不用重启）
#
# 必须用覆盖语义的 `substituters`：nix 按列表顺序逐个试源，`extra-substituters` 只会追加到末尾，
# 等于 icache 永不命中。列表不在这里重复维护 —— on 时现取系统列表拼在前面。
#
# 系统层已摘掉 icache（darwin: features/darwin/nix/_module.nix，nixos: features/nix/nix-settings.nix）；
# daemon 不重读系统 nix.conf，首次 switch 后用 `sudo launchctl kickstart -k system/systems.determinate.nix-daemon`
# 重启一次，之后 on/off 即时生效。root 跑的 nix（sudo / nixos-rebuild）读不到用户级配置，仍走系统列表。
{ config, ... }:
let
  mirrors = [
    "https://icache.int.ooooo.space/cache.nixos.org"
    "https://icache.int.ooooo.space/nix-community.cachix.org"
  ];
in
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.nix-icache ];
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.nix-icache ];

  flake.modules.homeManager.nix-icache =
    { lib, pkgs, ... }:
    let
      nix-icache = pkgs.writeShellApplication {
        name = "nix-icache";
        text = ''
          conf="$HOME/.config/nix/icache.conf"
          mirrors="${lib.concatStringsSep " " mirrors}"

          # 只读系统层，避免把已写入的 icache 再算一遍
          systemSubstituters() {
            NIX_USER_CONF_FILES=${pkgs.emptyFile} nix config show | sed -n 's/^substituters = //p'
          }

          case "''${1:-status}" in
            on)
              system=$(systemSubstituters)
              if [ -z "$system" ]; then
                echo "nix-icache: 读不到系统 substituters，未改动 $conf" >&2
                exit 1
              fi
              {
                echo "# 由 nix-icache 生成"
                echo "substituters = $mirrors $system"
              } > "$conf.tmp"
              mv "$conf.tmp" "$conf"
              echo "icache: on"
              ;;
            off)
              rm -f "$conf"
              echo "icache: off"
              ;;
            status)
              if [ -e "$conf" ]; then echo on; else echo off; fi
              ;;
            *)
              echo "用法: nix-icache [on|off|status]" >&2
              exit 2
              ;;
          esac
        '';
      };
    in
    {
      home.packages = [ nix-icache ];
      home.file.".config/nix/nix.conf".text = lib.mkAfter "!include icache.conf";
    };
}
