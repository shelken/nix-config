{
  # agenix,
  mylib,
  sops-nix,
  config,
  ...
}:
let
  # get-sops-file = file: secrets + "/sops/secrets/${file}";
  # user_readable = {
  #   mode = "0500";
  #   # owner = myvars.username;
  # };
  # get-default-sops-file = get-sops-file "${myvars.username}/default.yaml";
  # default-sops-secret = {
  #   sopsFile = get-default-sops-file;
  # }
  # // user_readable;
in
{
  imports = [
    # agenix.darwinModules.default
    # agenix.homeManagerModules.default
    # sops-nix
    sops-nix.homeManagerModules.sops
  ];

  # home.packages = with pkgs; [
  #   agenix.packages."${pkgs.system}".default
  # ];

  sops.age = {
    generateKey = true;
    keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    sshKeyPaths = [
      "${config.home.homeDirectory}/.ssh/id_ed25519"
    ];
  };
  # 统一linux 和 darwin
  home.sessionVariables.SOPS_AGE_KEY_FILE = config.sops.age.keyFile;

  sops.secrets = {
    # "deepseek/api-key" = mylib.mkDefaultSecret { };
    # "github/cli-token" = mylib.mkDefaultSecret { };
    "wakatime/conf" = mylib.mkDefaultSecret {
      path = "${config.home.homeDirectory}/.wakatime.cfg";
    };
    "asciinema/install-id" = mylib.mkDefaultSecret {
      path = "${config.home.homeDirectory}/.config/asciinema/install-id";
    };
  };

  # if you changed this key, you need to regenerate all encrypt files from the decrypt contents!
  # age.identityPaths = [
  #   # Generate manually via `sudo ssh-keygen -A`
  #   "/etc/ssh/ssh_host_ed25519_key" # macOS, using the host key for decryption
  # ];

  # age.secrets = let
  # in {
  #   # ---------------------------------------------
  #   # no one can read/write this file, even root.
  #   # ---------------------------------------------

  #   # ---------------------------------------------
  #   # only root can read this file.
  #   # ---------------------------------------------

  #   # ---------------------------------------------
  #   # user can read this file.
  #   # ---------------------------------------------

  #   # "rclone.conf" =
  #   #   {
  #   #     file = "${secrets}/secrets/fm/rclone.conf";
  #   #     path = "${config.home.homeDirectory}/.config/rclone/rclone.conf";
  #   #   }
  #   #   // user_readable;
  # };

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
