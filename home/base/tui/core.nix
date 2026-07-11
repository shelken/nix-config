{
  pkgs,
  pkgs-unstable,
  ...
}:
{
  home.packages = with pkgs; [
    age
    sops
    ssh-to-age

    #-- rust
    pkgs-unstable.cargo
    pkgs-unstable.rustc
    pkgs-unstable.rust-analyzer
    pkgs-unstable.rustfmt

    #-- deploy
    ansible
    ansible-lint
    sshpass

    #-- container

    # misc
    protobuf
    #oha  #压测工具: https://github.com/hatoo/oha
    asciinema # 终端录制命令与回放

    # ts
    pnpm

    # python
    uv # python 管理（uvx）

    # nix
    nh # Yet another nix cli helper

    # net
    q # dns dig
    nali # `traceroute 1.1.1.1 | nali` show geo location
  ];

  programs.npm.enable = true;
  programs.npm.settings = {
    prefix = "\${HOME}/.npm-global";
    # registry = "https://registry.npmmirror.com";
    min-release-age = 3;
    # 半开连接快速失败，不拉长重试等待
    fetch-timeout = 15000;
    fetch-retries = 1;
    fetch-retry-mintimeout = 500;
    fetch-retry-maxtimeout = 2000;
    maxsockets = 15;
  };

  # Bun HTTP 空闲超时/重试（IDLE 仅 1.3.14+；偏快速失败）
  home.sessionVariables = {
    BUN_CONFIG_HTTP_IDLE_TIMEOUT = "5";
    BUN_CONFIG_HTTP_RETRY_COUNT = "1";
  };

  home.shellAliases = {
    record = "asciinema rec --overwrite -i 1 --rows 28 --cols 140";
  };
}
