# router-mine 的声明（nuci 写法），编译与下发见 modules/features/network/openwrt/README.md
# 按功能分组，一个 UCI 配置文件一个 .nix，配置用到的包写在同一个文件里；这里只放可公开的部分
{
  imports = [
    ./system
    ./services
  ];
}
