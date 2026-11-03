#!/bin/sh

# 遇到错误立即退出
set -e

CURRENT_HOST=$(hostname)

echo "检查 Kopia 仓库连接..."
if ! kopia repository status >/dev/null; then
    echo "无法打开 Kopia 仓库，请检查 repository.config、KOPIA_PASSWORD 和 S3 后端。" >&2
    exit 1
fi

# 配置指纹:policy.json 内容 + webhook 配置(URL/severity)
# 状态文件存于 /config/cache(持久卷)，容器重建不丢；模板代码变更需删除该文件或 --force-recreate 后手动对账
STATE_FILE=/config/cache/.applied-config-hash
POLICY_HASH=$(sha256sum /config/policy.json 2>/dev/null | awk '{print $1}')
WEBHOOK_HASH=$(printf 'url=%s\nseverity=%s' "${KOPIA_WEBHOOK_URL:-}" "${KOPIA_MIN_SEVERITY:-report}" | sha256sum | awk '{print $1}')
FINGERPRINT="policy:${POLICY_HASH:-none} webhook:${WEBHOOK_HASH}"

if [ -n "$POLICY_HASH" ] && [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE" 2>/dev/null)" = "$FINGERPRINT" ]; then
    echo "配置未变更（policy/webhook 指纹一致），跳过对账。"
    SKIP_RECONCILE=1
else
    echo "配置变更，执行 policy/webhook 对账..."

    # 导入策略（幂等：先删除当前主机的路径策略，再导入）
    echo "清理旧的路径策略..."
    kopia policy list 2>/dev/null | grep "shelken@${CURRENT_HOST}:/" | awk '{print $1}' | while read -r target; do
        echo "  删除: $target"
        kopia policy remove "$target" 2>/dev/null || true
    done

    # 导入新策略
    kopia policy import --from-file /config/policy.json

    # 记录指纹
    echo "$FINGERPRINT" > "$STATE_FILE"
fi

# 如果设置了 Webhook URL，则配置通知（仅在对账时执行）
if [ -n "$KOPIA_WEBHOOK_URL" ] && [ "$SKIP_RECONCILE" != "1" ]; then
    echo "正在配置企业微信 Webhook 通知..."

    # 配置通知 Profile
    # KOPIA_MIN_SEVERITY 选项:
    #   - report: 每次备份完成都通知（包括成功）（默认值）
    #   - warning: 仅在失败/警告时通知（成功时不通知）
    #   - error: 仅在错误时通知
    KOPIA_MIN_SEVERITY="${KOPIA_MIN_SEVERITY:-report}"
    kopia notification profile configure webhook \
        --profile-name="wecom_webhook" \
        --endpoint="$KOPIA_WEBHOOK_URL" \
        --method="POST" \
        --http-header="Content-Type: application/json" \
        --format="txt" \
        --min-severity="$KOPIA_MIN_SEVERITY"

    # 设置模板
    # Kopia 模板必须包含 Subject: 头 + 空行 + 正文
    # 正文部分是企业微信 Webhook 接受的 JSON
    TEMPLATE_FILE="/tmp/snapshot-report-template.txt"
    cat >"$TEMPLATE_FILE" <<'TEMPLATE_EOF'
Subject: Kopia Backup {{.EventArgs.OverallStatus}}

{"msgtype":"markdown","markdown":{"content":"## Kopia 备份报告\n> **主机**: {{.Hostname}}\n> **状态**: {{.EventArgs.OverallStatus}}\n> **时间**: {{.EventTime.Format "2006-01-02 15:04:05"}}\n{{ range .EventArgs.Snapshots | sortSnapshotManifestsByName}}\n**路径**: `{{.Manifest.Source.Path}}`\n- 状态: {{.StatusCode}}\n- 大小: {{.TotalSize | bytes}}\n- 文件: {{.TotalFiles | formatCount}}\n{{ if .Error }}- 错误: {{.Error}}{{ end }}{{ end }}"}}
TEMPLATE_EOF

    kopia notification template remove "snapshot-report.txt" || true
    kopia notification template set "snapshot-report.txt" --from-file="$TEMPLATE_FILE"
    rm -f "$TEMPLATE_FILE"

    echo "通知配置完成: wecom_webhook"
else
    if [ "$SKIP_RECONCILE" = "1" ]; then
        echo "跳过对账，webhook 配置保持现状。"
    else
        echo "未设置 KOPIA_WEBHOOK_URL，跳过通知配置。"
    fi
fi

# 启动服务器
echo "正在启动 Kopia Server..."
# 默认参数：无密码模式，方便内网访问
# 可通过传入参数覆盖，例如: entrypoint.sh --address=0.0.0.0:8080 --password=xxx
if [ $# -eq 0 ]; then
    exec kopia server start --address=0.0.0.0:51515 --without-password --insecure --allow-extremely-dangerous-unauthenticated-server-on-the-network
else
    exec kopia server start "$@"
fi
