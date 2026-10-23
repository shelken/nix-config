# kube-pod-path-widget - 在命令行通过 fzf 交互式选择 K8s Pod 内部路径
# 用法: 命令行输入 <ns>/<pod>: 后按快捷键 (默认 ^k)

local ns pod tmp
tmp="${LBUFFER##* }"
ns="${tmp%%/*}"
pod="${tmp#*/}"; pod="${pod%%:*}"

[[ -z "$pod" ]] && zle redisplay && return 0

local remote_path="/"
while true; do
  local entries sel
  entries=$(kubectl exec -n "$ns" "$pod" -- ls -a -p "$remote_path" 2>/dev/null)
  [[ "$remote_path" != "/" ]] && entries="..\n${entries}"

  sel=$(echo "$entries" | fzf --prompt="${remote_path}> " --bind "q:abort")

  if [[ -z "$sel" ]]; then
    LBUFFER="${LBUFFER}${remote_path}"
    zle redisplay
    return 0
  fi

  if [[ "$sel" == ".." ]]; then
    remote_path="${remote_path%/*/}/"
    [[ -z "$remote_path" ]] && remote_path="/"
    continue
  fi

  local full="${remote_path%/}/${sel%/}"
  if [[ "$sel" == */ ]]; then
    remote_path="${full}/"
  else
    LBUFFER="${LBUFFER}${full}"
    zle redisplay
    return 0
  fi
done
