# SSH 服务端：OpenSSH、防火墙默认关闭、terminfo 全量安装
# 改名 openssh 而不叫 ssh：HM 侧同名功能 ssh 已在 core 里，同名挂接会让它被导入两次
# 所有 NixOS 主机都需要 → nixos.core
{ config, ... }:
{
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.openssh ];

  flake.modules.nixos.openssh =
    { lib, ... }:
    {
      # networking.firewall.allowedTCPPorts = [ ... ];
      # networking.firewall.allowedUDPPorts = [ ... ];
      # Or disable the firewall altogether.
      networking.firewall.enable = lib.mkDefault false;

      # Enable the OpenSSH daemon.
      services.openssh = {
        enable = true;
        settings = {
          X11Forwarding = true;
          # root user is used for remote deployment, so we need to allow it
          PermitRootLogin = "prohibit-password";
          PasswordAuthentication = false; # disable password login
        };
        openFirewall = true;
      };

      # Add terminfo database of all known terminals to the system profile.
      # https://github.com/NixOS/nixpkgs/blob/nixos-24.05/nixos/modules/config/terminfo.nix
      environment.enableAllTerminfo = true;
    };
}
