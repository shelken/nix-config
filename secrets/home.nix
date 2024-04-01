{
  agenix,
  secrets,
  config,
  ...
}: {
  imports = [
    # agenix.darwinModules.default
    agenix.homeManagerModules.default
  ];

  # home.packages = with pkgs; [
  #   agenix.packages."${pkgs.system}".default
  # ];

  # if you changed this key, you need to regenerate all encrypt files from the decrypt contents!
  # age.identityPaths = [
  #   # Generate manually via `sudo ssh-keygen -A`
  #   "/etc/ssh/ssh_host_ed25519_key" # macOS, using the host key for decryption
  # ];

  age.secrets = let
    user_readable = {
      mode = "0500";
      # owner = myvars.username;
    };
  in {
    # ---------------------------------------------
    # no one can read/write this file, even root.
    # ---------------------------------------------

    # ---------------------------------------------
    # only root can read this file.
    # ---------------------------------------------

    # ---------------------------------------------
    # user can read this file.
    # ---------------------------------------------

    "wakatime.cfg" =
      {
        file = "${secrets}/secrets/misc/wakatime.cfg";
        path = "${config.home.homeDirectory}/.wakatime.cfg";
      }
      // user_readable;
    "asciinema-install-id" =
      {
        file = "${secrets}/secrets/misc/asciinema-install-id.age";
        path = "${config.home.homeDirectory}/.config/asciinema/install-id";
      }
      // user_readable;
    "rclone.conf" =
      {
        file = "${secrets}/secrets/fm/rclone.conf";
        path = "${config.home.homeDirectory}/.config/rclone/rclone.conf";
      }
      // user_readable;
  };

  # both the original file and the symlink should be readable and executable by the user
  #
  # activationScripts are executed every time you run `nixos-rebuild` / `darwin-rebuild` or boot your system
  # system.activationScripts.postActivation.text = ''
  #   ${pkgs.nushell}/bin/nu -c '
  #     if (ls /etc/agenix/ | length) > 0 {
  #       sudo chown ${myvars.username} /etc/agenix/*
  #     }
  #   '
  # '';
}
