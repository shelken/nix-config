#compdef task

if [[ -f Taskfile.yaml || -f Taskfile.yml || -f Taskfile.dist.yaml || -f Taskfile.dist.yml ]]; then
  if ! typeset -f __task_list >/dev/null 2>&1; then
    eval "$(command task --completion zsh 2>/dev/null)"
  fi
  if typeset -f _task >/dev/null 2>&1; then
    _task "$@"
  fi
fi
