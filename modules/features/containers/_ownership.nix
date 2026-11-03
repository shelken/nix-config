{
  docker,
  lib,
  name,
}:
let
  probe = ''
    id=$(${docker}/bin/docker container ls --all --no-trunc --filter ${lib.escapeShellArg "name=^/${name}$"} --format '{{.ID}}')
    owner=""
    if [[ -n $id ]]; then
      owner=$(${docker}/bin/docker container inspect --format '{{index .Config.Labels "io.shelken.nix-managed"}}' "$id")
    fi
  '';
in
{
  check = probe + ''
    if [[ -n $id && $owner != true ]]; then
      echo "Refusing to replace an unmanaged container; complete the manual ownership handover first." >&2
      exit 1
    fi
  '';
  stop = probe + ''
    if [[ -n $id && $owner == true ]]; then
      ${docker}/bin/docker stop "$id"
    fi
  '';
  # 启动前检查失败也会执行 postStop，清理必须重新验证所有权。
  remove = probe + ''
    if [[ -n $id && $owner == true ]]; then
      ${docker}/bin/docker rm -f "$id"
    fi
  '';
}
