# zerotier 整套。network.nix、firewall.nix 贡献的是 network、firewall 两个文件的一部分，
# nuci 按整个文件声明，等 network/ 里这两个文件整份写全后再接入 imports，否则下发会删掉其余的段
{
  imports = [ ./zerotier.nix ];
}
