# 授权密钥与其他主机共用 vars.mainSshAuthorizedKeys。nuci 整份覆盖 authorized_keys，
# 部署者（本机 ssh-agent）的公钥不在列表里时会被追加，防止下发后把自己锁在外面
{ myvars, ... }:
{
  uci.sshKeys = myvars.mainSshAuthorizedKeys;

  uci.settings.dropbear.main = {
    _type = "dropbear";
    Interface = "lan";
    PasswordAuth = "off";
    Port = "22";
    RootPasswordAuth = "off";
    enable = "1";
  };
}
