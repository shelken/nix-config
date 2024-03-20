{
  pkgs,
  myvars,
  ...
} @ args: {
  environment.systemPackages = with pkgs; [
    git # used by nix flakes
    # git-lfs # used by huggingface models

    # archives
    zip
    # xz
    zst
    unzip
    p7zip

    # Text Processing
    # Docs: https://github.com/learnbyexample/Command-line-text-processing
    gnugrep # GNU grep, provides `grep`/`egrep`/`fgrep`
    gnused # GNU sed, very powerful(mainly for replacing text in files)
    gawk # GNU awk, a pattern scanning and processing language
    jq # A lightweight and flexible command-line JSON processor

    # networking tools
    mtr # A network diagnostic tool
    iperf3
    wget
    curl
    socat # replacement of openbsd-netcat
    nmap # A utility for network discovery and security auditing

    # misc
    file
    which
    tree
    rsync
  ];

  users.users.${myvars.username} = {
    description = myvars.userfullname;
    # Public Keys that can be used to login to all my PCs, Macbooks, and servers.
    #
    # Since its authority is so large, we must strengthen its security:
    # 1. The corresponding private key must be:
    #    1. Generated locally on every trusted client via:
    #      ```bash
    #      # KDF: bcrypt with 256 rounds, takes 2s on Apple M2):
    #      # Passphrase: digits + letters + symbols, 12+ chars
    #      ssh-keygen -t ed25519 -a 256 -C "ryan@xxx" -f ~/.ssh/xxx`
    #      ```
    #    2. Never leave the device and never sent over the network.
    # 2. Or just use hardware security keys like Yubikey/CanoKey.
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK1/TnqUWbdQgCcF1mXsgdMumR7EKGpyKn19SHzhFBuY shelken@macmini"
    ];
  };

  nix.settings = {
    # enable flakes globally
    experimental-features = ["nix-command" "flakes"];

    # given the users in this list the right to specify additional substituters via:
    #    1. `nixConfig.substituers` in `flake.nix`
    #    2. command line args `--options substituers http://xxx`
    trusted-users = [myvars.username];

    # substituers that will be considered before the official ones(https://cache.nixos.org)
    substituters = [
      # cache mirror located in China
      # status: https://mirror.sjtu.edu.cn/
      # "https://mirror.sjtu.edu.cn/nix-channels/store"
      # status: https://mirrors.ustc.edu.cn/status/
      "https://mirrors.ustc.edu.cn/nix-channels/store"

      "https://nix-community.cachix.org"
    ];

    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
    builders-use-substitutes = true;
  };
}
