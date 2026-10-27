#!/usr/bin/env bash
set -euo pipefail

# 环境唯一来源：generator 生成的 guest-env.sh。
# 该文件缺失说明 VM 未挂载生成配置，也就没有工具清单可补 —— 直接报错，不再维护第二份回退。
if [[ ! -f /run/sandbox-config/current/guest-env.sh ]]; then
  echo "[-] 错误: 沙箱内缺少 /run/sandbox-config/current/guest-env.sh，无法确定工具环境" >&2
  exit 1
fi
# shellcheck source=/dev/null
source /run/sandbox-config/current/guest-env.sh

# sync 是唯一安装路径：写入共用安装层与共用下载/缓存目录（MISE_DATA_DIR 由 guest-env.sh 按同一目录判断导出）
if [[ -d /opt/sandbox-mise/data ]]; then
  export MISE_CACHE_DIR=/opt/sandbox-mise/cache
  export MISE_DOWNLOADS_DIR=/opt/sandbox-mise/data/downloads
  mkdir -p "$MISE_DATA_DIR" "$MISE_CACHE_DIR" "$MISE_DOWNLOADS_DIR"
fi
export GIT_CONFIG_GLOBAL="@git_config@"

# guest 的 HTTPS 出口由 msb 重签证书，只信任镜像里的 /etc/ssl/certs/ca-certificates.crt（内容就是 msb 的 CA）。
# Nix 的公共 CA bundle 会报「self-signed certificate in certificate chain」，所以没有回落
ca_bundle=/etc/ssl/certs/ca-certificates.crt
[[ -r "$ca_bundle" ]] || { echo "[-] 错误: guest 里缺少 $ca_bundle（msb 的 CA）" >&2; exit 1; }
export SSL_CERT_FILE="$ca_bundle" CURL_CA_BUNDLE="$ca_bundle" GIT_SSL_CAINFO="$ca_bundle"

# 确保 /data 基础目录结构存在
mkdir -p /data/mise /data/xdg/data/mise /data/xdg/cache/mise /data/xdg/config/mise "$MISE_SHIMS_DIR" /data/xdg/data/omp
# 上下文外（sb sync、msb exec）看到的配置：每个可写根在 /root 下指向只读发布目录。
# 根清单与 launcher 同源（发布目录的 writable-roots）；本脚本随同一版本发布，清单必然存在
while IFS= read -r root; do
  [[ -n "$root" ]] || continue
  mkdir -p "$(dirname "/root/$root")"
  ln -sfn "/run/sandbox-config/current/$root" "/root/$root" 2>/dev/null || true
done < /run/sandbox-config/current/writable-roots

# 沙箱内插件安装失败必须传给 sb sync；宿主激活的容忍策略不受影响
export SB_POSTINSTALL_STRICT=1

# 1. 补齐 mise 工具 (幂等：已安装的不重新下载、不升级；永远只补缺)
echo "[sb sync] 1. 补齐 mise 工具清单..."
if ! command -v mise >/dev/null 2>&1; then
  echo "[-] 错误: guest 内未找到 mise，无法补齐工具" >&2
  exit 1
fi
# set -e 下安装失败必须让 sync 非零退出，不能吞成「全部已装」
mise install --yes
# 普通 reshim：只补新增 shim，不先清空目录，避免运行中上下文短暂找不到命令
mise reshim

# 2. 运行共享工具 postInstall 步骤（按清单 bun install 只补缺，不删除现有依赖）
echo "[sb sync] 2. 执行工具 postInstall (重放插件清单)..."
@postinstall_steps@

echo "[sb sync] 工具与插件补齐成功。"