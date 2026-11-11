# ssh：客户端配置
{ config, ... }:
{
  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.ssh ];

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
}
