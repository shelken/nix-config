# 用户账号：authorized_keys（modules/base/users.nix 迁入）
{
  flake.modules.nixos.user-account =
    { myvars, ... }:
    {
      users.users.${myvars.username} = {
        description = myvars.userfullname;
        # Public Keys that can be used to login to all my PCs, Macbooks, and servers.
        #
        # Since its authority is so large, we must strengthen its security:
        # 1. The corresponding private key must be:
        #    1. Generated locally on every trusted client via:
        #      ```bash
        #      # KDF: bcrypt with 256 rounds, takes 2s on Apple M2):
        #      # Passphrase: digits + letters + symbols, 12+ chars
        #      ssh-keygen -t ed25519 -a 256 -C "ryan@xxx" -f ~/.ssh/xxx`
        #      ```
        #    2. Never leave the device and never sent over the network.
        # 2. Or just use hardware security keys like Yubikey/CanoKey.
        openssh.authorizedKeys.keys = myvars.mainSshAuthorizedKeys;
      };
    };

  # darwin 侧同样的 authorizedKeys 写入 /etc/ssh/nix_authorized_keys.d/<user>
  # （nix-darwin 的 users.users.<user>.openssh 行为，原 modules/base/users.nix 同时作用于两平台）
  flake.modules.darwin.user-account =
    { myvars, ... }:
    {
      users.users.${myvars.username}.openssh.authorizedKeys.keys = myvars.mainSshAuthorizedKeys;
    };
}
