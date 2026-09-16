{
  inputs,
  lib,
  system,
  genSpecialArgs,
  nixos-modules,
  home-modules ? [ ],
  myvars,
  ...
}:
let
  inherit (inputs) nixpkgs home-manager nixos-generators;
  specialArgs = genSpecialArgs system;
in
nixpkgs.lib.nixosSystem {
  inherit system specialArgs;
  modules =
    nixos-modules
    ++ [
      nixos-generators.nixosModules.all-formats
    ]
    ++ (lib.optionals ((lib.lists.length home-modules) > 0) [
      home-manager.nixosModules.home-manager
      (
        { config, ... }:
        {
          home-manager.useGlobalPkgs = true;
          # 整份机器配置是 Home 的唯一权威：包装进用户 profile，激活用 driver 0
          # 维护同一个 home-manager generation profile，与 `just hm` 的局部应用共用
          # 同一份激活结果和历史入口，不产生第二套 Home 事实来源。
          home-manager.useUserPackages = false;
          home-manager.enableLegacyProfileManagement = true;

          home-manager.extraSpecialArgs = specialArgs // {
            hostname = config.networking.hostName;
          };
          home-manager.users."${myvars.username}".imports = home-modules;
        }
      )
    ]);
}
