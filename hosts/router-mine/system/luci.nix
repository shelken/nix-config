# LuCI 界面固定中文：ImmortalWrt 首启把 luci.main.lang 设成 auto，界面随浏览器语言变成英文。
# luci 配置里其余段由软件包维护，声明整个文件会删掉它们，所以只用 rawUci 改这一项。
# nuci 只给 settings 里的配置自动 commit，rawUci 要自己 commit，否则重启后丢失
{
  uci.rawUci = [
    "uci set luci.main.lang='zh_cn'"
    "uci commit luci"
  ];
}
