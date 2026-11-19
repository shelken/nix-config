# home-ops 的路由器指标：集群里的 Prometheus 抓取，homepage 路由器小组件与链路降速告警都读它（home-ops 的 #1800）。
# netclass、netdev、loadavg、cpu 采集器都在基础包里。exporter 自带一个 uhttpd 实例，与 LuCI 的 uhttpd 互不相干
{
  uci.packages = [ "prometheus-node-exporter-lua" ];

  uci.settings.prometheus-node-exporter-lua.main = {
    _type = "prometheus-node-exporter-lua";
    # lan 区域入站本就放行，Prometheus 经 K8s 节点从 lan 来
    listen_interface = "lan";
    listen_port = "9100";
  };
}
