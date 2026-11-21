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
          "gnu-sed"
          "gnu-tar"
          "git-trim"
        ];
      };
    };

  flake.modules.homeManager.homebrew =
    { pkgs, ... }:
    let
      envExtra = ''
        export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
      '';
    in
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "brew-diff";
          runtimeInputs = with pkgs; [
            gawk
          ];
          text = ''
            brewfile=$(nix path-info /run/current-system --recursive 2>/dev/null | awk '/Brewfile/ && !found { print; found = 1 }')
            if [[ -z $brewfile ]]; then
              echo "Error: 未在 /run/current-system 中找到 Brewfile" >&2
              exit 1
            fi
            brew bundle cleanup --file="$brewfile"
          '';
        })
      ];
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
