{ inputs, ... }:
{
  flake.modules.nixos.sops =
    { lib, ... }:
    {
      imports = [ inputs.sops-nix.nixosModules.sops ];

      sops.age = {
        keyFile = "/var/lib/sops-nix/key.txt";
        sshKeyPaths = lib.mkForce [ ];
      };
      sops.gnupg.sshKeyPaths = lib.mkForce [ ];
    };

  flake.modules.nixos.sops-passwords =
    {
      config,
      lib,
      myvars,
      ...
    }:
    {
      sops.secrets = {
        "${myvars.username}-password-hash".neededForUsers = lib.mkDefault true;
        root-password-hash.neededForUsers = lib.mkDefault true;
      };

      users.users = {
        ${myvars.username} = {
          initialHashedPassword = lib.mkForce null;
          hashedPasswordFile = lib.mkDefault config.sops.secrets."${myvars.username}-password-hash".path;
        };
        root = {
          initialHashedPassword = lib.mkForce null;
          hashedPasswordFile = lib.mkDefault config.sops.secrets.root-password-hash.path;
        };
      };
    };
}
