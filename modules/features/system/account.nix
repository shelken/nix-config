{ config, ... }:
{
  flake.modules.nixos.core.imports = [ config.flake.modules.nixos.account ];
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.account ];

  flake.modules.nixos.account =
    {
      config,
      lib,
      myvars,
      ...
    }:
    {
      users.mutableUsers = false;

      users.groups.${myvars.username} = { };

      users.users.${myvars.username} = {
        description = myvars.userfullname;
        home = "/home/${myvars.username}";
        isNormalUser = true;
        extraGroups = [
          myvars.username
          "users"
          "wheel"
        ]
        ++ lib.optional config.networking.networkmanager.enable "networkmanager"
        ++ lib.optional config.virtualisation.docker.enable "docker";
        openssh.authorizedKeys.keys = myvars.mainSshAuthorizedKeys;
      };

      users.users.root = {
        openssh.authorizedKeys.keys = myvars.mainSshAuthorizedKeys;
      };
    };

  flake.modules.darwin.account =
    { myvars, ... }:
    {
      users.users.${myvars.username} = {
        home = "/Users/${myvars.username}";
        openssh.authorizedKeys.keys = myvars.mainSshAuthorizedKeys;
      };
    };

  flake.modules.homeManager.account =
    { osConfig, myvars, ... }:
    {
      home.homeDirectory = osConfig.users.users.${myvars.username}.home;
    };
}
