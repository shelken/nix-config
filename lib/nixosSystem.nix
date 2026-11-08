{
  inputs,
  mylib,
  system,
  specialArgs,
  nixos-modules,
  home-modules ? [ ],
  myvars,
  ...
}:
let
  inherit (inputs) nixpkgs home-manager;
in
nixpkgs.lib.nixosSystem {
  inherit system specialArgs;
  modules = nixos-modules ++ [
    home-manager.nixosModules.home-manager
    (mylib.mkHomeManagerModule { inherit myvars specialArgs home-modules; })
  ];
}
