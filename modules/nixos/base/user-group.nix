{
  myvars,
  config,
  ...
}: {
  # Don't allow mutation of users outside the config.
  users.mutableUsers = false;

  users.groups = {
    "${myvars.username}" = {};
    docker = {};
  };

  users.users."${myvars.username}" = {
    # generated by `mkpasswd -m scrypt`
    # we have to use initialHashedPassword here when using tmpfs for /
    initialHashedPassword = "$7$CU..../....GbQ7xUejtHNrAoHWD6Qta/$T22s4jQMYtvlcRGN09nFRgWaJi5ll.rjezwyb6L.ZFD";
    home = "/home/${myvars.username}";
    isNormalUser = true;
    extraGroups = [
      myvars.username
      "users"
      "networkmanager"
      "wheel"
      "docker"
    ];
  };

  # root's ssh key are mainly used for remote deployment
  users.users.root = {
    initialHashedPassword = config.users.users."${myvars.username}".initialHashedPassword;
    openssh.authorizedKeys.keys = config.users.users."${myvars.username}".openssh.authorizedKeys.keys;
  };

  # DO NOT promote the specified user to input password for `nix-store` and `nix-copy-closure`
  # security.sudo.extraRules = [
  #   {
  #     users = [myvars.username];
  #     commands = [
  #       {
  #         command = "/run/current-system/sw/bin/nix-store";
  #         options = ["NOPASSWD"];
  #       }
  #       {
  #         command = "/run/current-system/sw/bin/nix-copy-closure";
  #         options = ["NOPASSWD"];
  #       }
  #     ];
  #   }
  # ];
}
