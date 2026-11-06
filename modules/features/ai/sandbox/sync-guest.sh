#!/usr/bin/env bash
# sb sync 在 VM 内执行的脚本；环境（路径、PATH、mise 目录）由 _guest.nix 的包装加载 guest-env.sh。
set -euo pipefail

export MISE_CACHE_DIR="$SB_MISE_CACHE_DIR"
export MISE_DOWNLOADS_DIR="$SB_MISE_DATA_DIR/downloads"
mkdir -p "$MISE_DOWNLOADS_DIR"

# guest 的 HTTPS 出口由 msb 重签证书，只信任镜像里的 /etc/ssl/certs/ca-certificates.crt（内容就是 msb 的 CA）。
# Nix 的公共 CA bundle 会报「self-signed certificate in certificate chain」，所以没有回落
[[ -r "$GIT_SSL_CAINFO" ]] || { echo "[-] 错误: guest 里缺少 $GIT_SSL_CAINFO（msb 的 CA）" >&2; exit 1; }
export SSL_CERT_FILE="$GIT_SSL_CAINFO" CURL_CA_BUNDLE="$GIT_SSL_CAINFO"

while IFS= read -r root; do
  [[ -n "$root" ]] || continue
  mkdir -p "$(dirname "/root/$root")"
  ln -sfn "$SB_CONFIG_DIR/$root" "/root/$root"
done < "$SB_CONFIG_DIR/writable-roots"

# 沙箱内插件安装失败必须传给 sb sync；宿主激活的容忍策略不受影响
export SB_POSTINSTALL_STRICT=1

echo "[sb sync] 1. 补齐 mise 工具清单..."
# 幂等：已安装的不重新下载、不升级，永远只补缺。set -e 下安装失败必须让 sync 非零退出
mise install --yes
# 普通 reshim：只补新增 shim，不先清空目录，避免运行中上下文短暂找不到命令
mise reshim

echo "[sb sync] 2. 执行工具 postInstall (重放插件清单)..."
"$SB_POSTINSTALL_HOOK"
echo "[sb sync] 工具与插件补齐成功。"
