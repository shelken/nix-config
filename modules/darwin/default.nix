{pkgs, myvars, ...}: {

  users.users."${myvars.username}" = {
    home = "/Users/${myvars.username}";

    # set user's default shell back to zsh
    #    `chsh -s /bin/zsh`
    # DO NOT change the system's default shell to nushell! it will break some apps!
    # It's better to change only kitty/wezterm's shell to nushell!
  }; 

  imports = [
    ../base.nix
    ./apps.nix
    ./system.nix
    ./shell.nix
  ];

  ###################################################################################
  #
  #  Core configuration for nix-darwin
  #
  #  All the configuration options are documented here:
  #    https://daiderd.com/nix-darwin/manual/index.html#sec-options
  #
  # History Issues:
  #  1. Fixed by replace the determinated nix-installer by the official one:
  #     https://github.com/LnL7/nix-darwin/issues/149#issuecomment-1741720259
  #
  ###################################################################################

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Auto upgrade nix package and the daemon service.
  services.nix-daemon.enable = true;
  nix.package = pkgs.nix;

  # Disable auto-optimise-store because of this issue:
  #   https://github.com/NixOS/nix/issues/7273
  # "error: cannot link '/nix/store/.tmp-link-xxxxx-xxxxx' to '/nix/store/.links/xxxx': File exists"
  nix.settings.auto-optimise-store = false;

  nix.gc.automatic = false;
}
