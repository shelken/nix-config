{
  every = 7200; # 每 2h
  user = false; # 日志属主 root
  script = ''
    # 保留最新一份 Loon 隧道日志，其余删除
    # 日志名即时间戳（YYYY-MM-DD HH:MM:SS.log），字典序 = 时间序，无需 stat（且规避 BSD/GNU stat 语法分歧）
    if [ "$(id -u)" -ne 0 ]; then
      echo "日志文件属主为 root，请用: sudo task-loon" >&2
      exit 1
    fi
    dir="/Library/Application Support/com.loon.Loon/tunnelLog"
    [ -d "$dir" ] || exit 0
    latest=$(find "$dir" -type f -name '*.log' | sort -r | head -1)
    [ -n "$latest" ] || exit 0
    find "$dir" -type f -name '*.log' ! -path "$latest" -delete
  '';
}
