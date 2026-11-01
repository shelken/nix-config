# 激活时给列出的目录打 Time Machine 排除标记（选项值来自 darwin 侧的 osConfig），
# 并每天检查各目的地多久没备份成功，超过阈值即以任务失败发通知
#
# 幂等：已带 com.apple.metadata:com_apple_backup_excludeItem 就跳过。
# 实测同一台机器上 xattr -p 约 35ms，而 tmutil addexclusion 每个路径 1~11 秒（视 TM 守护进程状态），
# 所以不能每次激活都无条件调用：全部已排除时整个片段 0.06 秒，新排除一个目录才付一次秒级代价。
# 目录不存在则跳过且不代建：备份不到就没有排除的意义，代建工具的状态目录
# 反而可能改变这些工具「目录已存在即已初始化」的判断。
# 标记是目录上的 xattr，目录被删掉重建后一并消失，所以每次激活都要重放一遍。
#
# macOS 自带 /usr/bin/xattr 与 /usr/bin/tmutil，与 nix-darwin 调 /usr/bin/defaults 同一思路。
{
  flake.modules.homeManager.time-machine =
    {
      config,
      lib,
      osConfig,
      ...
    }:
    let
      # `~/x` → 具体路径：公开仓库里不写死用户名
      expandHome =
        path:
        if lib.hasPrefix "~/" path then
          "${config.home.homeDirectory}/${lib.removePrefix "~/" path}"
        else
          path;

      paths = map expandHome osConfig.shelken.darwin.timeMachine.excludePaths;

      # TM 备份连续失败时只在设置面板里显示，不会主动通知
      staleDays = 3;
    in
    lib.mkMerge [
      {
        # 数据源只能是偏好：tmutil latestbackup/listbackups 要 Full Disk Access，
        # 直接读 plist 文件也被 TCC 拦，defaults export 走 cfprefsd 则不受限。
        # SnapshotDates 只在成功后出现，从未成功的新目的地退回用首次尝试时间计龄
        shelken.tasks.time-machine-check = {
          when = "12:00";
          notify.title = "Time Machine 备份过期";
          script = ''
            prefs=$(/usr/bin/defaults export /Library/Preferences/com.apple.TimeMachine -)
            field() { /usr/bin/plutil -extract "$1" raw -o - - <<<"$prefs" 2>/dev/null; }

            if ! count=$(field Destinations); then
              echo "没有配置 Time Machine 目的地"
              exit 0
            fi

            now=$(/bin/date +%s)
            stale=0
            for ((i = 0; i < count; i++)); do
              name=$(field "Destinations.$i.LastKnownVolumeName") || name="#$i"
              if n=$(field "Destinations.$i.SnapshotDates"); then
                ref=$(field "Destinations.$i.SnapshotDates.$((n - 1))")
                label="上次成功"
              elif field "Destinations.$i.AttemptDates" >/dev/null; then
                ref=$(field "Destinations.$i.AttemptDates.0")
                label="首次尝试，至今未成功"
              else
                continue
              fi
              days=$(((now - $(/bin/date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$ref" +%s)) / 86400))
              echo "''${name}: ''${label} ''${ref}，距今 ''${days} 天，RESULT=$(field "Destinations.$i.RESULT")"
              if [ "$days" -ge ${toString staleDays} ]; then
                stale=1
              fi
            done
            exit "$stale"
          '';
        };
      }
      (lib.mkIf (paths != [ ]) {
        home.activation.timeMachineExclusions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          excludeFromBackup() {
            _tm_path="$1"
            if [ ! -e "$_tm_path" ]; then
              echo "time-machine: 跳过不存在的路径 $_tm_path"
            elif /usr/bin/xattr -p com.apple.metadata:com_apple_backup_excludeItem "$_tm_path" > /dev/null 2>&1; then
              :
            else
              # 失败只告警：排除是尽力而为，不该挡住激活
              if /usr/bin/tmutil addexclusion "$_tm_path"; then
                echo "time-machine: 新排除 $_tm_path"
              else
                echo "time-machine: 警告：排除失败 $_tm_path" >&2
              fi
            fi
          }

          ${lib.concatMapStringsSep "\n" (path: "excludeFromBackup ${lib.escapeShellArg path}") paths}
        '';
      })
    ];
}
