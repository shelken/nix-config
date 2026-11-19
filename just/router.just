# OpenWrt 路由器（nuci）的维护任务，由根 justfile 以 `mod router` 引入：just router::<配方>

# 模块配方默认在本文件所在目录执行，这里统一回到仓库根目录，相对路径才与根 justfile 一致
set working-directory := '..'

target := 'root@router-mine'
# 每次按最新声明重新编译，改完 hosts/router-mine/ 不用单独构建
uci := 'nix build .#router-mine-uci --no-link --print-out-paths'
# 声明里的 {{ sops.<路径> }} 由 sops -d 解密 secrets.nix 的 router-mine.yaml 后展开成明文（规则见 render.jq），
# 只落在临时目录，退出即删；编译产物在 nix store 里只含占位符。sops 解不开、占位符在 yaml 里没有值时报错退出。
# sops 文件路径取自 uci 包的 passthru.sopsFile（flake 的 secrets 输入）；解密需要 SOPS_AGE_KEY_FILE 指向 admin_mio 的 age 密钥。
# nuci 的 diff 会原样打印路由器上现有的值（删除行也会），所以输出必须经 mask：
# 从未展开的声明里找出写了 {{ sops.… }} 的 文件.段.选项，把输出中这些键的值打码（规则见 mask.jq）
nuci := '''
esc=$'\033'
src=$(''' + uci + ''')
sops_file=$(nix eval --raw .#router-mine-uci.sopsFile)
mask_expr=$(jq -r --arg esc "$esc" -f modules/features/network/openwrt/mask.jq "$src")
# 兜底：被删除的条目声明里没有占位符，规则覆盖不到，MAC 与由 MAC 推出的 IPv6 后缀（EUI-64）一律打码
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
    # 热点中继在 LuCI 里开启时，声明里它是关闭的，下发会把它关掉并让路由器断网
    # 刚刷完的系统没有 wifinet7 段，视为关闭
    [ "$(ssh -- "$host" 'if uci -q get wireless.wifinet7 >/dev/null; then uci -q get wireless.wifinet7.disabled; else echo 1; fi')" = 1 ] || { echo '热点中继（wifinet7）已启用，先在 LuCI 关掉再下发' >&2; exit 1; }
    avahi_before=$(ssh -- "$host" 'md5sum /etc/avahi/avahi-daemon.conf')
    {{ nuci }}deploy "$tmp/uci.json" --target "$host" 2>&1 | mask
    # bird -p 校验失败时不重载，BIRD 继续跑旧配置
    ssh -- "$host" 'bird -p -c /etc/bird.conf && birdc configure'
    [ "$avahi_before" = "$(ssh -- "$host" 'md5sum /etc/avahi/avahi-daemon.conf')" ] || ssh -- "$host" '/etc/init.d/avahi-daemon restart'

# 固件经 ASU 云端构建，镜像只放本机，旧镜像由 asu 脚本清理；锁文件提交进仓库
firmware_dir := env('XDG_DATA_HOME', home_directory() / '.local/share') / 'router-firmware/router-mine'

[private]
_firmware mode:
    modules/features/network/openwrt/asu {{ mode }} "$(nix build .#router-mine-firmware --no-link --print-out-paths)" "$({{ uci }})" hosts/router-mine/firmware.lock.json '{{ firmware_dir }}'

[doc('按软件源当前版本构建固件并重写锁文件，不改设备；审查 git diff 后提交')]
firmware-update: (_firmware 'update')

[doc('按锁文件构建并下载固件，包版本与锁文件不一致时失败，不改设备')]
firmware-build: (_firmware 'build')

# 刷机前后各跑一次 acceptance，结果含设备运行数据，只放本机
acceptance_dir := firmware_dir / 'acceptance'

[doc('采集验收数据：路由器状态（只读）与本机 WiFi 到 sakamoto 的吞吐，结果存本机')]
acceptance:
    modules/features/network/openwrt/acceptance run {{ target }} sakamoto '{{ acceptance_dir }}'

[doc('并排对比两份验收结果，用法: just router::acceptance-diff <前.json> <后.json>')]
acceptance-diff before after:
    modules/features/network/openwrt/acceptance diff '{{ before }}' '{{ after }}'
