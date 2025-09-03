{myvars, ...}: {
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
  };
}
