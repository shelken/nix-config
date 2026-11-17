# zt 接口的设备名由网络 ID 派生，在 secrets.nix 的 sops（router-mine.yaml 的 zerotier）
{
  uci.settings.network.zt = {
    _type = "interface";
    device = "{{ sops.zerotier.device }}";
    proto = "none";
  };
}
