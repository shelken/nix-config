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
}
