{
  config,
  lib,
  pkgs,
  ...
}:
##########################################################################
#
#  Install all apps and packages here.
#
#  NOTE: Your can find all available options in:
#    https://daiderd.com/nix-darwin/manual/index.html
#
#  NOTE：To remove the uninstalled APPs icon from Launchpad:
#    1. `sudo nix store gc --debug` & `sudo nix-collect-garbage --delete-old`
#    2. click on the uninstalled APP's icon in Launchpad, it will show a question mark
#    3. if the app starts normally:
#        1. right click on the running app's icon in Dock, select "Options" -> "Show in Finder" and delete it
#    4. hold down the Option key, a `x` button will appear on the icon, click it to remove the icon
#
# TODO Fell free to modify this file to fit your needs.
#
##########################################################################
let
  # Homebrew Mirror
  # NOTE: is only useful when you run `brew install` manually! (not via nix-darwin)
  homebrew_mirror_env = {
    HOMEBREW_API_DOMAIN = "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api";
    HOMEBREW_BOTTLE_DOMAIN = "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles";
    HOMEBREW_BREW_GIT_REMOTE = "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git";
    HOMEBREW_CORE_GIT_REMOTE = "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git";
    HOMEBREW_PIP_INDEX_URL = "https://pypi.tuna.tsinghua.edu.cn/simple";
  };

  local_proxy_env = {
    # HTTP_PROXY = "http://127.0.0.1:7890";
    # HTTPS_PROXY = "http://127.0.0.1:7890";
  };

  homebrew_env_script = lib.attrsets.foldlAttrs (
    acc: name: value:
    acc + "\nexport ${name}=${value}"
  ) "" (homebrew_mirror_env // local_proxy_env);
in
{
  # Install packages from nix's official package repository.
  #
  # The packages installed here are available to all users, and are reproducible across machines, and are rollbackable.
  # But on macOS, it's less stable than homebrew.
  #
  # Related Discussion: https://discourse.nixos.org/t/darwin-again/29331
  environment.systemPackages = with pkgs; [
    neovim
    git
    gnugrep # replacee macos's grep
    #gnutar # replacee macos's tar

    # darwin only apps
  ];
  environment.variables = {
    # Fix https://github.com/LnL7/nix-darwin/wiki/Terminfo-issues
    TERMINFO_DIRS = map (path: path + "/share/terminfo") config.environment.profiles ++ [
      "/usr/share/terminfo"
    ];

    EDITOR = "nvim";
  }
  # Set variables for you to manually install homebrew packages.
  // homebrew_mirror_env;

  # Set environment variables for nix-darwin before run `brew bundle`.
  system.activationScripts.homebrew.text = lib.mkBefore ''
    echo >&2 '${homebrew_env_script}'
    ${homebrew_env_script}
  '';

  # Create /etc/zshrc that loads the nix-darwin environment.
  # this is required if you want to use darwin's default shell - zsh
  programs.zsh.enable = true;
  environment.shells = [
    pkgs.zsh
  ];

  # homebrew need to be installed manually, see https://brew.sh
  # https://github.com/LnL7/nix-darwin/blob/master/modules/homebrew.nix
  homebrew = {
    enable = true; # disable homebrew for fast deploy

    onActivation = {
      autoUpdate = lib.mkDefault false;
      # 'zap': uninstalls all formulae(and related files) not listed in the generated Brewfile
      # cleanup = "uninstall";
    };

    # Applications to install from Mac App Store using mas.
    # You need to install all these Apps manually first so that your apple account have records for them.
    # otherwise Apple Store will refuse to install them.
    # For details, see https://github.com/mas-cli/mas
    masApps = {
      # Wechat = 836500024;
      # Xnip = 1221250572;
      # DiskSpeedTest = 425264550;
      # vidhub = 1659622164;
    };

    taps = [
      #"homebrew/cask-fonts"
      "homebrew/services"
      #"homebrew/cask-versions"
      "shelken/tap" # self tap

      "hashicorp/tap" # terraform
      "FelixKratz/formulae" # jankyborders
      "gromgit/fuse" # macfuse,mounty
      "nikitabobko/tap" # aerospace
      "bigwig-club/brew" # upic
      "mhaeuser/mhaeuser" # battery-toolkit
    ];

    brews = [
      # `brew install`
      "wget" # download tool
      "curl" # no not install curl via nixpkgs, it's not working well on macOS!
      # "aria2" # download tool
      # "httpie" # http client
      "xh" # same as httpie. but faster

      # https://github.com/rgcr/m-cli
      "m-cli" #  Swiss Army Knife for macOS
      "proxychains-ng"

      # commands like `gsed` `gtar` are required by some tools
      "gnu-sed"
      "gnu-tar"

      # misc that nix do not have cache for.
      "git-trim"
    ];

    # `brew install --cask`
    casks = [
      # input-source
      "squirrel-app" # input method for Chinese, rime-squirrel

      # browser
      # "google-chrome"
      "helium-browser"

      # Misc
      "raycast" # macOS 12+ (HotKey: alt/option + space)search, calculate and run scripts(with many plugins)
      "stats" # beautiful system status monitor in menu bar
      "pearcleaner" # pearcleaner
      "the-unarchiver" # zip,unzip
      "parsec"
      "mac-mouse-fix" # 鼠标滚动

      # keyborader
      "karabiner-elements" # 快捷键映射

      # network
      "tailscale-app"

      # quicklook
      "qlmarkdown"
      "syntax-highlight"

      # Development
      # "kitty"
      "visual-studio-code"
      # "wezterm"
    ];
  };
}
