{ myvars, ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = {
      "*" = {
        forwardAgent = false;
        addKeysToAgent = "yes";
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
