# 可选功能：需要的 NixOS 主机在 imports 里加 self.modules.nixos.sops，并设置 sops.defaultSopsFile
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
