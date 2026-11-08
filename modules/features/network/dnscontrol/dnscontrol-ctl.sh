#!/usr/bin/env bash
# dnscontrol 的唯一入口：把 sops 里的私密值注入 config/dnsconfig.js，再交给 dnscontrol

usage() {
  cat >&2 <<'EOF'
用法: dnscontrol-ctl <preview|push|check|print-ir>

  preview    对比线上记录与 dnsconfig.js，只显示差异（输出为空即已同步）
  push       把差异推到线上 DNS。务必先 preview
  check      只校验 dnsconfig.js 语法与变量，不访问 Cloudflare
  print-ir   打印展开后的中间表示（调试用）

域名、公网 IP、DCV 标识与 Cloudflare token 取自 sops（键清单见 README.md），
变量经 -v 传给 dnsconfig.js，token 经环境变量传给 creds.json。
配置目录：~/.config/dnscontrol
EOF
  exit 2
}

(( $# == 1 )) || usage
sub=$1
case $sub in
  preview | push | check | print-ir) ;;
  *) usage ;;
esac

read_secret() {
  local name=$1 file=$2 value
  if ! value=$(< "$file") || [[ -z $value ]]; then
    echo "读不到 sops 的 $name：$file（本机未启用 secrets，或还没激活过）" >&2
    return 1
  fi
  printf '%s' "$value"
}

domain=$(read_secret main-domain "$DOMAIN_FILE")
vps_v4=$(read_secret dnscontrol/vps-ipv4 "$VPS_V4_FILE")
vps_v6=$(read_secret dnscontrol/vps-ipv6 "$VPS_V6_FILE")
vps_v6_secondary=$(read_secret dnscontrol/vps-ipv6-secondary "$VPS_V6_SECONDARY_FILE")
cf_dcv_id=$(read_secret dnscontrol/cf-dcv-id "$CF_DCV_ID_FILE")

args=(
  "$sub"
  --config "$CONFIG_DIR/dnsconfig.js"
  -v "domain=$domain"
  -v "vps_v4=$vps_v4"
  -v "vps_v6=$vps_v6"
  -v "vps_v6_secondary=$vps_v6_secondary"
  -v "cf_dcv_id=$cf_dcv_id"
)

# check 与 print-ir 不访问 Cloudflare，没有 --creds，也不需要 token
if [[ $sub == preview || $sub == push ]]; then
  CLOUDFLARE_API_TOKEN=$(read_secret dnscontrol/cloudflare-api-token "$CLOUDFLARE_API_TOKEN_FILE")
  export CLOUDFLARE_API_TOKEN
  args+=(--creds "$CONFIG_DIR/creds.json")
fi

exec mise exec -- dnscontrol "${args[@]}"
