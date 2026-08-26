{
  every = 7200; # 每 2h
  user = false; # 日志属主 root
  script = ''
    # 保留最新一份 Loon 隧道日志，其余删除
    dir="/Library/Application Support/com.loon.Loon/tunnelLog"
    [ -d "$dir" ] || exit 0
    latest=$(find "$dir" -type f -name '*.log' -exec stat -f '%m %N' {} + | sort -rn | head -1 | cut -d' ' -f2-)
    [ -n "$latest" ] || exit 0
    find "$dir" -type f -name '*.log' ! -path "$latest" -delete
  '';
}
