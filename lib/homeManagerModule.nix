{
  myvars,
  specialArgs,
  home-modules,
}:
{ config, ... }:
{
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = false;
  home-manager.enableLegacyProfileManagement = true;

  home-manager.extraSpecialArgs = specialArgs // {
    hostname = config.networking.hostName;
  };
  home-manager.users."${myvars.username}".imports = home-modules;
}
