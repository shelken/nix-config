# SSH 服务端：OpenSSH、仅密钥登录、terminfo 全量安装；防火墙保持 NixOS 默认（开启）
# 改名 openssh 而不叫 ssh：HM 侧同名功能 ssh 已在 core 里，同名挂接会让它被导入两次
# 所有 NixOS 主机都需要 → nixos.core
{ config, ... }:
{
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.openssh ];

  flake.modules.nixos.openssh = {
    # Enable the OpenSSH daemon.
    services.openssh = {
      enable = true;
      settings = {
        # root user is used for remote deployment, so we need to allow it
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = false; # disable password login
        KbdInteractiveAuthentication = false;
      };
      openFirewall = true;
    };

    # Add terminfo database of all known terminals to the system profile.
    # https://github.com/NixOS/nixpkgs/blob/nixos-24.05/nixos/modules/config/terminfo.nix
    environment.enableAllTerminfo = true;

    # sshd 以登录用户身份读 /etc/ssh/authorized_keys.d/<用户>：/etc/ssh 不是 755 时，
    # 普通用户读不到自己的公钥，只有 root 能登录。nixos-anywhere --extra-files 会原样带入
    # 随装目录里 etc/ssh 的权限，NixOS 激活不改目录本身，这里每次激活与开机都纠正
    systemd.tmpfiles.rules = [ "z /etc/ssh 0755 root root -" ];
  };
}
