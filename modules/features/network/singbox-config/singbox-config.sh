#!/usr/bin/env bash
# 生成 mac / ios / router 的订阅 URL：填充 1Password 模板 → encode（URL 进剪切板）

usage() {
  cat >&2 <<'EOF'
用法: singbox-config <mac|ios|router>

把 templates/<变体>.yaml 里的 1Password 引用填充成真实配置，再 encode 成订阅 URL。
URL 由 sbtools 写进剪切板。私密值只落在临时目录，退出即删。

模板里用到的 1Password 条目（都在 vault Personal 的 proxy 条目里，一个字段一项）：
  subs-miaona        机场订阅 URL
  vps-hy2            \
  vps-hy2-v6          > 私有节点 URI（mac / router 三条，ios 两条）
  vps-anytls         /
  clash-secret       router 的 clash API secret

订阅服务地址取 sops 的 main-domain，脚本里拼成 https://subs.<main-domain>。
router overlay 里的本网解析器地址（dns-lan）、部署域名与内网入口、放行解析器清单、
白名单源 IP 都直接写在 templates/router.yaml。
EOF
  exit 2
}

(( $# == 1 )) || usage
variant=$1
case $variant in
  mac | ios | router) ;;
  *) usage ;;
esac

main_domain_file="@mainDomainFile@"
if [[ ! -r $main_domain_file ]]; then
  echo "读不到 sops 密文：$main_domain_file（本机未启用 secrets，或还没激活过）" >&2
  exit 1
fi
main_domain=$(< "$main_domain_file")
if [[ -z $main_domain ]]; then
  echo "sops 的 main-domain 是空的：$main_domain_file" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
yaml="$work/$variant.yaml"

echo "→ 填充模板：@templatesDir@/$variant.yaml"
sec-run op inject -i "@templatesDir@/$variant.yaml" -o "$yaml"
chmod 600 "$yaml"

# 不跑 sbtools check：那一步要启动 sing-box 内核，本机没装就报「启动内核失败（sing-box）」。
# 想校验就先装内核，再手动 `sbtools check -c <填充后的 yaml>`
echo "→ 生成订阅 URL（写入剪切板）"
mise exec -- sbtools encode -s "https://subs.$main_domain" -c "$yaml"
