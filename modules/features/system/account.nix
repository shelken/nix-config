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
        initialHashedPassword = lib.mkDefault myvars.initialHashedPassword;
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
        initialHashedPassword = lib.mkDefault myvars.initialHashedPassword;
        openssh.authorizedKeys.keys = myvars.mainSshAuthorizedKeys;
      };
    };

  # darwin 侧同样的 authorizedKeys 写入 /etc/ssh/nix_authorized_keys.d/<user>
  # （nix-darwin 的 users.users.<user>.openssh 行为）
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
