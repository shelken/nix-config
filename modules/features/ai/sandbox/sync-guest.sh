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

# sync 是唯一安装路径：写入共用安装层与共用下载/缓存目录
if [[ -d /opt/sandbox-mise/data ]]; then
  export MISE_DATA_DIR=/opt/sandbox-mise/data
  export MISE_CACHE_DIR=/opt/sandbox-mise/cache
  export MISE_DOWNLOADS_DIR=/opt/sandbox-mise/data/downloads
  mkdir -p "$MISE_DATA_DIR" "$MISE_CACHE_DIR" "$MISE_DOWNLOADS_DIR"
fi
export GIT_CONFIG_GLOBAL="@git_config@"

# 插件含私有 GitHub 仓库（git+ssh），guest 无 SSH key。
# msb secrets 只在网络边界替换占位符，因此这里用占位符拼出 https 凭据 URL；
# 占位符仅在发往 allow 名单内主机的请求中被替换成真实 token（宿主 sb.yaml 已声明）。
# 用独立配置文件并 include 宿主配置，避免覆盖原有 credential/insteadOf 规则。
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  mkdir -p /data/sandbox-sync
  cat > /data/sandbox-sync/gitconfig <<'GITCFG'
[url "https://x-access-token:$MSB_GITHUB_TOKEN@github.com/"]
insteadOf = https://github.com/
insteadOf = git@github.com:
insteadOf = git+ssh://git@github.com/
insteadOf = ssh://git@github.com/
GITCFG
  export GIT_CONFIG_GLOBAL=/data/sandbox-sync/gitconfig
fi
export GIT_TERMINAL_PROMPT=0

# CA 证书：guest 里优先用镜像/Nix 实际存在的 bundle。
# 先前的顺序把宿主 store 路径排在最前，guest 里不存在时会静默保留错误的 SSL_CERT_FILE，
# 导致所有 https 请求报「self-signed certificate in certificate chain」。
ca_bundle=""
for candidate in /etc/ssl/certs/ca-certificates.crt "@cacert@/etc/ssl/certs/ca-bundle.crt"; do
  if [[ -r "$candidate" ]]; then
    ca_bundle="$candidate"
    break
  fi
done
if [[ -n "$ca_bundle" ]]; then
  export SSL_CERT_FILE="$ca_bundle"
  export CURL_CA_BUNDLE="$ca_bundle"
  export GIT_SSL_CAINFO="$ca_bundle"
fi

# 确保 /data 与 /root 基础目录结构存在
mkdir -p /data/mise /data/xdg/data/mise /data/xdg/cache/mise /data/xdg/config/mise "$MISE_SHIMS_DIR" /data/omp/plugins /root/.omp
ln -sfn /run/sandbox-config/current/.omp/agent /root/.omp/agent 2>/dev/null || true
ln -sfn /data/omp/plugins /root/.omp/plugins 2>/dev/null || true
# OMP 在 $XDG_DATA_HOME/omp 存在时读 $XDG_DATA_HOME/omp/plugins，与安装位置 /data/omp/plugins 对齐
mkdir -p /data/xdg/data/omp
ln -sfn /data/omp/plugins /data/xdg/data/omp/plugins
if [[ -e /run/sandbox-config/current/.pi ]]; then
  ln -sfn /run/sandbox-config/current/.pi /root/.pi 2>/dev/null || true
fi
if [[ -e /run/sandbox-config/current/.agents ]]; then
  ln -sfn /run/sandbox-config/current/.agents /root/.agents 2>/dev/null || true
fi

# 沙箱内插件安装失败必须传给 sb sync；宿主激活的容忍策略不受影响
export SB_POSTINSTALL_STRICT=1

# 1. 补齐 mise 工具 (幂等：已安装的不重新下载、不升级；永远只补缺)
# 先精确查出缺失规格再逐个安装：mise ls --missing 失败必须让 sync 非零退出，
# 不能用 2>/dev/null … || true 吞掉后按空缺失列表继续 —— 那会把「查询失败」伪装成「全部已装」
echo "[sb sync] 1. 补齐 mise 工具清单..."
if ! command -v mise >/dev/null 2>&1; then
  echo "[-] 错误: guest 内未找到 mise，无法补齐工具" >&2
  exit 1
fi
missing_json="$(mise ls --missing --json)" || {
  echo "[-] 错误: mise ls --missing 查询失败" >&2
  exit 1
}
missing_specs_raw="$(printf '%s' "$missing_json" | jq -r 'to_entries[] | .key as $k | .value[] | "\($k)@\(.version)"')" || {
  echo "[-] 错误: 解析 mise ls --missing 输出失败" >&2
  exit 1
}
missing_specs=()
while IFS= read -r spec; do
  [[ -n "$spec" ]] && missing_specs+=("$spec")
done <<< "$missing_specs_raw"
if [[ ${#missing_specs[@]} -eq 0 ]]; then
  echo "[sb sync] 所有 mise 工具均已安装，本次不发起任何安装"
else
  echo "[sb sync] 待安装: ${missing_specs[*]}"
  mise install --yes "${missing_specs[@]}"
fi
# 普通 reshim：只补新增 shim，不先清空目录，避免运行中上下文短暂找不到命令
mise reshim

# 2. 运行共享工具 postInstall 步骤（按清单 bun install 只补缺，不删除现有依赖）
echo "[sb sync] 2. 执行工具 postInstall (重放插件清单)..."
@postinstall_steps@

echo "[sb sync] 工具与插件补齐成功。"