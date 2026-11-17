# ssh：客户端配置（所有主机 → HM core）与服务端 OpenSSH（所有 NixOS 主机 → nixos.core）
# 服务端模块叫 openssh 而不叫 ssh：HM 的 ssh 已在 HM core 里，同名挂接会让它在 NixOS 上被导入两次
{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.ssh ];
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.openssh ];

  flake.modules.homeManager.ssh =
    { myvars, pkgs, ... }:
    {
      # macOS 自带 agent 的 socket 路径只有 GUI 会话知道，SSH 登录进来的会话找不到；
      # 这里起一个路径可推导的 agent，本地与远程会话共用同一份已解锁的钥匙
      services.ssh-agent.enable = pkgs.stdenv.hostPlatform.isDarwin;

      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
        settings = {
          "*" = {
            forwardAgent = false;
            addKeysToAgent = "8h";
            UseKeychain = "yes";
            # 变更原因：Home Manager 的 raw SSH `SetEnv` 选项要求 attrset，生成 `SetEnv TERM="..."`。
            SetEnv = {
              TERM = "xterm-256color";
            };
          };
        };
        extraConfig = ''
          Host github.com
            User git
            HostName ssh.github.com
            Port 443
          ${myvars.networking.ssh.extraConfig}
        '';
        # 用户特定的需要额外加的host
        includes = [
          "~/.ssh/specific"
        ];
      };
    };

  # 仅密钥登录、terminfo 全量安装；防火墙保持 NixOS 默认（开启）
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
  };
}
