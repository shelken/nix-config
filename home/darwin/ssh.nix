{...}: {
  programs.ssh = {
    enable = true;
    # 用户特定的需要额外加的host
    includes = [
      "~/.ssh/specific"
    ];
  };
}
