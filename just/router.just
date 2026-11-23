set working-directory := '..'

target := 'root@router-mine'
uci := 'nix build .#router-mine-uci --no-link --print-out-paths'
# nuci 的 diff 会原样打印路由器上现有的值（删除行也会），所以输出必须经 mask：
nuci := '''
esc=$'\033'
src=$(''' + uci + ''')
sops_file=$(nix eval --raw .#router-mine-uci.sopsFile)
mask_expr=$(jq -r --arg esc "$esc" -f modules/features/network/openwrt/mask.jq "$src")
mask() { sed -E -e "$mask_expr" -e 's/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/<MAC>/g' -e 's/[0-9A-Fa-f:]*ff:fe[0-9A-Fa-f:]*/<EUI64>/g'; }
umask 077
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
sops -d --output-type json "$sops_file" > "$tmp/secrets.json"
jq --slurpfile secrets "$tmp/secrets.json" -f modules/features/network/openwrt/render.jq "$src" > "$tmp/uci.json"
mise exec -- nuci '''

[doc('只读：把路由器上某个配置文件的现状转成 nuci 写法并打印，用法: just router::import dhcp')]
import config:
    @modules/features/network/openwrt/uci2nix {{ target }} {{ config }}

[doc('对比声明与路由器现状，不改设备；可传 SSH 目标，例如 just router::preview root@192.168.1.1')]
preview $host=target:
    #!/usr/bin/env bash
    set -euo pipefail
    {{ nuci }}diff "$tmp/uci.json" --target "$host" 2>&1 | mask

# nuci 对 uci.files 只写文件：不校验也不重载服务，所以 BIRD 与 avahi 的生效在下发之后补做
[doc('把声明下发到路由器，会改设备；先用同一个 SSH 目标运行 just router::preview')]
push $host=target:
    #!/usr/bin/env bash
    set -euo pipefail
    # 热点中继在 LuCI 里开启时，声明里它是关闭的，下发会把它关掉并让路由器断网；
    # 直接查设备上所有启用中的 sta 段，不依赖声明中的段名（改名或临时段都能拦住）；刚刷完无 wireless 文件视为关闭
    active_sta=$(ssh -- "$host" 'if [ -f /etc/config/wireless ]; then ubus call uci get '\''{"config":"wireless"}'\''; else echo "{}"; fi' |
      jq -r '[.values // {} | to_entries[] | select(.value[".type"] == "wifi-iface" and .value.mode == "sta" and (.value.disabled // "0") != "1") | .key] | join(",")')
    [ -z "$active_sta" ] || { echo "热点中继（$active_sta）已启用，先在 LuCI 关掉再下发" >&2; exit 1; }
    avahi_before=$(ssh -- "$host" 'md5sum /etc/avahi/avahi-daemon.conf')
    {{ nuci }}deploy "$tmp/uci.json" --target "$host" 2>&1 | mask
    ssh -- "$host" 'bird -p -c /etc/bird.conf && birdc configure'
    [ "$avahi_before" = "$(ssh -- "$host" 'md5sum /etc/avahi/avahi-daemon.conf')" ] || ssh -- "$host" '/etc/init.d/avahi-daemon restart'

firmware_dir := env('XDG_DATA_HOME', home_directory() / '.local/share') / 'router-firmware/router-mine'
builder := 'root@homelab-1'

[private]
_firmware mode:
    modules/features/network/openwrt/asu {{ mode }} "$(nix build .#router-mine-firmware --no-link --print-out-paths)" "$({{ uci }})" hosts/router-mine/firmware.lock.json '{{ firmware_dir }}'

[private]
_firmware-local mode $host=builder:
    modules/features/network/openwrt/build-local {{ mode }} "$(nix build .#router-mine-firmware --no-link --print-out-paths)" "$({{ uci }})" "$(nix eval --json .#router-mine-firmware.imagebuilder)" hosts/router-mine/firmware.lock.json '{{ firmware_dir }}' "$host"

[doc('按软件源当前版本构建固件并重写锁文件，不改设备；审查 git diff 后提交')]
firmware-update: (_firmware 'update')

[doc('按锁文件构建并下载固件，包版本与锁文件不一致时失败，不改设备')]
firmware-build: (_firmware 'build')

[doc('在本地构建节点用官方 ImageBuilder 构建固件并重写锁文件，不改设备；可指定 SSH 目标')]
firmware-update-local $host=builder: (_firmware-local 'update' host)

[doc('在本地构建节点按锁文件构建并下载固件，包版本与锁文件不一致时失败，不改设备；可指定 SSH 目标')]
firmware-build-local $host=builder: (_firmware-local 'build' host)

# sysupgrade 刷写时会杀掉 ubusd（246）或 dropbear（255），两者均属正常断连；其它非零退出码视为失败
[doc('按锁文件刷入固件并保留配置，会重启路由器；先 just router::acceptance 采基线')]
upgrade $host=target:
    #!/usr/bin/env bash
    set -euo pipefail
    lock=hosts/router-mine/firmware.lock.json
    [[ -f $lock ]] || { echo '没有锁文件，先运行 just router::firmware-update 或 just router::firmware-update-local' >&2; exit 1; }
    firmware=$(nix build .#router-mine-firmware --no-link --print-out-paths)
    uci=$({{ uci }})
    request=$(jq -n --slurpfile f "$firmware" --slurpfile u "$uci" '
      $f[0] | del(.server) + {
        packages: ($f[0].packages + $u[0].packages | unique),
        client: "nix-config"
      }')
    [[ $(jq -S .request "$lock") == "$(jq -S . <<<"$request")" ]] || {
      echo '声明与锁文件的请求不一致，先运行 just router::firmware-update 或 just router::firmware-update-local' >&2
      exit 1
    }
    image='{{ firmware_dir }}'/"$(jq -r .image.name "$lock")"
    expected_sha=$(jq -r .image.sha256 "$lock")
    if [[ ! -f $image ]] || [[ $(shasum -a 256 "$image" | cut -d' ' -f1) != "$expected_sha" ]]; then
      echo "本机缺少与锁文件匹配的镜像: $image（先运行 just router::firmware-build 或 just router::firmware-build-local）" >&2
      exit 1
    fi
    ssh -- "$host" 'cat > /tmp/sysupgrade.bin' < "$image"
    [ "$(ssh -- "$host" 'sha256sum /tmp/sysupgrade.bin' | cut -d' ' -f1)" = "$expected_sha" ] || { echo '上传后的镜像 sha256 与锁文件不符' >&2; exit 1; }
    ssh -- "$host" 'sysupgrade -T /tmp/sysupgrade.bin'
    rc=0
    ssh -- "$host" 'sysupgrade /tmp/sysupgrade.bin' || rc=$?
    [ "$rc" -eq 0 ] || [ "$rc" -eq 246 ] || [ "$rc" -eq 255 ] || exit "$rc"
    echo '路由器正在刷写并重启，约 3 分钟后跑 just router::acceptance 与 acceptance-diff'

acceptance_dir := firmware_dir / 'acceptance'

[doc('采集验收数据：路由器状态（只读）与本机 WiFi 到 sakamoto 的吞吐，结果存本机')]
acceptance:
    modules/features/network/openwrt/acceptance run {{ target }} sakamoto '{{ acceptance_dir }}'

[doc('并排对比两份验收结果，用法: just router::acceptance-diff <前.json> <后.json>')]
acceptance-diff before after:
    modules/features/network/openwrt/acceptance diff '{{ before }}' '{{ after }}'
