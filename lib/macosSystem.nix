{
  inputs,
  mylib,
  darwin-modules,
  home-modules ? [ ],
  myvars,
  system,
  specialArgs,
  ...
}:
let
  inherit (inputs) home-manager nix-darwin nixpkgs-darwin;
in
nix-darwin.lib.darwinSystem {
  inherit system specialArgs;
  modules = darwin-modules ++ [
    {
      nixpkgs.pkgs = import nixpkgs-darwin {
        inherit system;
        config.allowUnfree = true;
      };
    }
    home-manager.darwinModules.home-manager
    (mylib.mkHomeManagerModule { inherit myvars specialArgs home-modules; })
  ];
}
