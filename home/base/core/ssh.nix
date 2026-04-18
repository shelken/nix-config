{ myvars, ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks."*" = {
      forwardAgent = false;
      addKeysToAgent = "yes";
      extraOptions = {
        UseKeychain = "yes";
      };
    };
    extraConfig = ''
      ${myvars.networking.ssh.extraConfig}
    '';
    # 用户特定的需要额外加的host
    includes = [
      "~/.ssh/specific"
    ];
  };
}
