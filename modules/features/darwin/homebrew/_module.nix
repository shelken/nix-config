{
  config,
  lib,
  pkgs,
  ...
}:
let
  homebrew_mirror_env = {
    HOMEBREW_PIP_INDEX_URL = "https://pypi.tuna.tsinghua.edu.cn/simple";
    HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS = "1";
  };
in
{
  environment.systemPackages = with pkgs; [
    neovim
    git
    gnugrep
  ];

  environment.variables = {
    TERMINFO_DIRS = map (path: path + "/share/terminfo") config.environment.profiles ++ [
      "/usr/share/terminfo"
    ];
    EDITOR = "nvim";
  }
  // homebrew_mirror_env;

  programs.zsh.enable = true;
  environment.shells = [
    pkgs.zsh
  ];

  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = lib.mkDefault true;
      extraEnv.HOMEBREW_NO_REQUIRE_TAP_TRUST = "1";
      cleanup = lib.mkDefault "uninstall";
    };

    masApps = { };

    taps = [
      {
        name = "shelken/tap";
        trusted = true;
      }
      {
        name = "nikitabobko/tap";
        trusted = true;
      }
      {
        name = "bigwig-club/brew";
        trusted = true;
      }
    ];

    brews = [
      "just"
      "mas"
      "wget"
      "curl"
      "aria2"
      "xh"
      "m-cli"
      "proxychains-ng"
      "gnu-sed"
      "gnu-tar"
      "git-trim"
    ];
  };
}
