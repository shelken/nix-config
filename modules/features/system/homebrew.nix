# Homebrew 基础：镜像环境变量、常用 taps/brews、zsh 与终端基础包
# 所有 darwin 主机都需要 → darwin.core
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.homebrew ];

  flake.modules.darwin.homebrew =
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
    };

  # Homebrew 装在 /opt/homebrew（Apple Silicon）或 /usr/local（Intel），两处都加进 PATH
  flake.modules.homeManager.homebrew =
    let
      envExtra = ''
        export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
      '';
    in
    {
      programs.bash = {
        enable = true;
        bashrcExtra = envExtra;
      };
      programs.zsh = {
        enable = true;
        inherit envExtra;
      };
    };
}
