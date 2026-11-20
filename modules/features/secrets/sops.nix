{ inputs, ... }:
{
  flake.modules.nixos.sops =
    { lib, ... }:
    {
      imports = [ inputs.sops-nix.nixosModules.sops ];

      sops.age = {
        keyFile = "/var/lib/sops-nix/key.txt";
        # 默认会把 SSH 主机密钥转成 age 密钥，这里明确不用
        sshKeyPaths = lib.mkForce [ ];
      };
      sops.gnupg.sshKeyPaths = lib.mkForce [ ];
    };
}
