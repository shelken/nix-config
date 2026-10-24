# 让 nix 能把 Linux 构建交给本机的官方 darwin.linux-builder-vz（Apple Virtualization.framework）
#
# 背景：Determinate Native Linux Builder 因 FlakeHub 上 rosetta-guest 解析 404 不可用
# （DeterminateSystems/nix-src#730）。上游修复后，从主机 imports 里删掉本功能即可恢复。
#
# 排查结论（避免重复走弯路）：
#   - 404 始于 2026-10-23 15:30Z（上次成功 15:10Z），是服务端变化；与本机 Rosetta 无关：
#     macOS 27 升级会移除 Rosetta，装回后仍然 404
#   - determinate-nixd builder 传 --kernel/--initrd 也绕不过：daemon 仍会向 FlakeHub 解析 guest
#   - 修改 nix.custom.conf 后 daemon 不会重读，需要执行一次
#     sudo launchctl kickstart -k system/systems.determinate.nix-daemon
#   - guest 默认只有 1 核、约 2.9 GB 内存；调大要改 guest 配置，会失去缓存，需先有可用 builder
#
# 启停手动：
#   启动：linux-builder        （首次会要一次 sudo 密码，用来安装连接密钥）
#   停止：在该终端按 Ctrl-C    （vzvm 会先让 guest 优雅关机）
# VM 没启动时，Linux 构建会因连不上 linux-builder 而失败。
#
# 可选功能：要用的主机在 imports 里加 self.modules.darwin.linux-builder
# 不用 nix-darwin 的 nix.linux-builder：它要求 nix.enable = true，与 Determinate 接管 Nix 冲突
{ ... }:
{
  flake.modules.darwin.linux-builder =
    { lib, pkgs, ... }:
    let
      # nixpkgs builder 镜像内置的公开 host key，只用于本机回环连接
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUpCV2N4Yi9CbGFxdDFhdU90RStGOFFVV3JVb3RpQzVxQkorVXVFV2RWQ2Igcm9vdEBuaXhvcwo=";

      # create-builder 把密钥和磁盘镜像写在当前目录，固定到状态目录避免散落
      start = pkgs.writeShellApplication {
        name = "linux-builder";
        text = ''
          dir="$HOME/.local/state/linux-builder"
          mkdir -p "$dir"
          cd "$dir"
          exec ${pkgs.darwin.linux-builder-vz}/bin/create-builder
        '';
      };
    in
    {
      environment.systemPackages = [ start ];

      # 端口 31022 是 darwin.linux-builder-vz 的默认转发端口；密钥由它首次启动时生成并安装到 /etc/nix
      environment.etc."ssh/ssh_config.d/100-linux-builder.conf".text = ''
        Host linux-builder
          User builder
          Hostname localhost
          HostKeyAlias linux-builder
          Port 31022
          IdentityFile /etc/nix/builder_ed25519
      '';

      # 与 features/darwin/nix/_module.nix 里的 nix.custom.conf 合并（lines 类型按行拼接）
      environment.etc."nix/nix.custom.conf".text = lib.mkAfter ''
        builders = ssh-ng://builder@linux-builder aarch64-linux,x86_64-linux /etc/nix/builder_ed25519 4 - - - ${publicHostKey}
      '';
    };
}
