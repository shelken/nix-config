{ ... }:
{
  # macOS 27 appstored ArcadeResetPO 死循环防护 (issue #82)
  # 每小时巡检，仅在时间落入过去(触发死循环条件)时介入
  every = 3600;
  script = ''
    # 仅在 ArcadePayoutResetDate 落入过去(逾期触发死循环)时介入顶到 7 天后并重启 agent:
    # 正常未来时间保持 no-op，避免健康状态下被误触发
    d="$(defaults read com.apple.appstored ArcadePayoutResetDate 2>/dev/null)" || exit 0
    ts="$(date -j -f '%Y-%m-%d %H:%M:%S %z' "$d" +%s 2>/dev/null)" || exit 0
    now="$(date +%s)"
    if [ "$ts" -le "$now" ]; then
      defaults write com.apple.appstored ArcadePayoutResetDate -date "$(date -v+7d -u +%Y-%m-%dT%H:%M:%SZ)" || exit 1
      killall appstoreagent 2>/dev/null || true
    fi
  '';
}
