# 共用 mise 安装层 (MiseLayer)：宿主目录、guest 挂载点、挂载模式与上下文环境的唯一定义
# 消费方：_manifest（目录创建）、_guest（guest-env 与 launcher 的挂载和环境）、_host（sb 的挂载参数）
# 这里不写 shell：策略以数据形式给出，各消费方按自己的语言落地
{ homeDir }:
rec {
  # 宿主上的安装目录，所有 VM 共用；新 VM 不必重新下载
  hostDir = "${homeDir}/Data/sandboxes/mise/aarch64-linux";

  # 所有 VM 一律把宿主目录挂到这里。上限指纹只含 guest 侧声明，不含宿主真实路径
  guestMount = "/opt/sandbox-mise";

  # 上下文可写：项目自己的 mise.toml 声明的工具要能在上下文里 `mise install`，产物落在宿主并跨 VM 复用
  # 威胁模型只防误操作，只读挡不住 Agent 在项目里下载并运行程序（理由见 README「共用 mise 安装层」）
  mountMode = "rw";

  # bubblewrap 里转挂这个目录时用的绑定参数，由 mountMode 推出
  bwrapBind = if mountMode == "rw" then "--bind" else "--ro-bind";

  # 只在执行上下文的进程里设置，sb sync 不带：
  # 不用 MISE_OFFLINE，它连安装下载也禁止；PREFER_OFFLINE 只在本地已有版本时不联网，
  # 已装的 latest（如 minio/mc，版本列表约 14 MB，超过 mise 超时）不再每次启动白等。
  # sync 要联网解析版本，所以不能放进 guest-env.sh
  contextEnv = {
    MISE_PREFER_OFFLINE = "1";
  };
}
