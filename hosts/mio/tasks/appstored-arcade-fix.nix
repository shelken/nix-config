{ ... }:
{
  # macOS 27 appstored ArcadeResetPO 死循环防护 (issue #82)
  when = [
    "0:10"
    "12:10"
  ];
  script = ''
    # 距 ArcadePayoutResetDate 不足 24h(或已过期)时顶到 7 天后并重启 agent:
    # 远期日期会被 appstoreagent 判 invalid 重算, 近未来日期有效且永不到期
    d="$(defaults read com.apple.appstored ArcadePayoutResetDate 2>/dev/null)" || exit 0
    ts="$(date -j -f '%Y-%m-%d %H:%M:%S %z' "$d" +%s 2>/dev/null)" || exit 0
    now="$(date +%s)"
    if [ $(( ts - now )) -lt 86400 ]; then
      defaults write com.apple.appstored ArcadePayoutResetDate -date "$(date -v+7d -u +%Y-%m-%dT%H:%M:%SZ)"
      killall appstoreagent 2>/dev/null || true
    fi
  '';
}
