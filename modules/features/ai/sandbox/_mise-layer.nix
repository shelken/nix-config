{ homeDir }:
{
  hostDir = "${homeDir}/Data/sandboxes/mise/aarch64-linux";

  guestMount = "/opt/sandbox-mise";

  dataSub = "data";
  cacheSub = "cache";

  # 不用 MISE_OFFLINE，它连安装下载也禁止；PREFER_OFFLINE 只在本地已有版本时不联网，
  # 已装的 latest（如 minio/mc，版本列表约 14 MB，超过 mise 超时）不再每次启动白等。
  contextEnv = {
    MISE_PREFER_OFFLINE = "1";
  };
}
