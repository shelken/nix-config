{ homeDir }:
{
  hostDir = "${homeDir}/Data/sandboxes/mise/aarch64-linux";

  guestMount = "/opt/sandbox-mise";

  dataSub = "data";
  cacheSub = "cache";

  # 不用 MISE_OFFLINE，它连安装下载也禁止；PREFER_OFFLINE 只在本地已有版本时不联网，
  contextEnv = {
    MISE_PREFER_OFFLINE = "1";
  };
}
