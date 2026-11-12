# zt 接口的设备名由网络 ID 派生，取自 1Password（router-mine 条目的 zerotier 分组）
{
  uci.settings.network.zt = {
    _type = "interface";
    device = "{{ op://Personal/router-mine/zerotier/device }}";
    proto = "none";
  };
}
