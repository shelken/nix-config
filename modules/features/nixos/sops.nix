# 系统密钥：sops-nix 的 NixOS 模块，供系统服务在激活时读取（如登录口令哈希）
# 可选功能：需要的 NixOS 主机在 imports 里加 self.modules.nixos.sops，并设置 sops.defaultSopsFile
#
# 与 features/secrets（用户态凭据、shelken.secrets.enable）无关：这里只让主机自己解密给自己的文件。
# age 私钥由安装时 --extra-files 放到固定路径，不从 SSH 主机密钥派生，
# 这样 SSH 主机密钥泄露或轮换都不影响密文
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
