{ myvars, ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks."*" = {
      forwardAgent = false;
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
}
