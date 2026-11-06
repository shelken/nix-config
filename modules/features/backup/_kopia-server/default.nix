# vps-cc 与 sakamoto 的 kopia 服务端（云端仓库与本地仓库）共用的东西：
# 同一个仓库被两个版本的 kopia 写入有风险，镜像、入口脚本与策略只在这里写一份
{
  image = "kopia/kopia:0.23.1@sha256:89fd95ee2942880ca00eae964266958a394421ddbdf69bca62e38afc55f5900e";
  entrypoint = ./entrypoint.sh;
  policy = ./policy.json;
}
