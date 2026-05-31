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
        # 变更原因：Home Manager 的 raw SSH `SetEnv` 选项要求 attrset，生成 `SetEnv TERM="..."`。
        SetEnv = {
          TERM = "xterm-256color";
        };
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
