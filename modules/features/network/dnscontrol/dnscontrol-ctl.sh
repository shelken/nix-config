#!/usr/bin/env bash
# dnscontrol 的唯一入口：配置由 sops-nix 解密到 CONFIG_DIR，token 经环境变量交给 creds.json

usage() {
  cat >&2 <<'USAGE'
用法: dnscontrol-ctl <preview|push|check|print-ir>

  preview    对比线上记录与配置，只显示差异（输出为空即已同步）
  push       把差异推到线上 DNS。务必先 preview
  check      只校验配置语法，不访问 Cloudflare
  print-ir   打印展开后的中间表示（调试用）

配置在 ~/.config/dnscontrol/dnsconfig.js，由 sops 解密而来；改它见 README.md。
Cloudflare token 取自 sops 的 dnscontrol/cloudflare-api-token。
USAGE
  exit 2
}

(( $# == 1 )) || usage
sub=$1
case $sub in
  preview | push | check | print-ir) ;;
  *) usage ;;
esac

if [[ ! -r $CONFIG_DIR/dnsconfig.js ]]; then
  echo "读不到 $CONFIG_DIR/dnsconfig.js（本机未启用 secrets，或还没激活过）" >&2
  exit 1
fi

args=("$sub" --config "$CONFIG_DIR/dnsconfig.js")

# check 与 print-ir 不访问 Cloudflare，没有 --creds，也不需要 token
if [[ $sub == preview || $sub == push ]]; then
  if ! token=$(< "$CLOUDFLARE_API_TOKEN_FILE") || [[ -z $token ]]; then
    echo "读不到 sops 的 dnscontrol/cloudflare-api-token：$CLOUDFLARE_API_TOKEN_FILE（本机未启用 secrets，或还没激活过）" >&2
    exit 1
  fi
  export CLOUDFLARE_API_TOKEN=$token
  args+=(--creds "$CONFIG_DIR/creds.json")
fi

exec mise exec -- dnscontrol "${args[@]}"
