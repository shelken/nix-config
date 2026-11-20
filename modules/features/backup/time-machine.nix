# 为什么不用 SkipPaths：它存在 /Library/Preferences/com.apple.TimeMachine.plist，`tmutil addexclusion -p`
# 实测无 root 时报 "requires root privileges"（exit 80），有 root 时还要求 Full Disk Access；
# 而激活脚本从终端跑（`just sw`），终端没有该权限，`-p` 这条路走不通。
# 改用 `tmutil addexclusion <路径>`（不带 -p）：只给目标打 sticky xattr
# com.apple.metadata:com_apple_backup_excludeItem，普通用户权限即可，不需要授权。
{ lib, ... }:
{
  flake.modules.darwin.time-machine =
    { config, ... }:
    {
      options.shelken.darwin.timeMachine.excludePaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "~/Data/sandboxes"
          "~/.lima"
          "~/.orbstack"
          "~/Parallels"
          "~/Library/Containers/com.utmapp.UTM"
          "~/.cache"
          "~/.vscode"
          "~/Library/Developer"
          "~/go/pkg/mod"
          "~/.npm"
          "~/.cargo/registry"
          "~/.cargo/git"
          "~/.local/share/mise"
          "~/.local/share/uv"
          "~/.npm-global"
          "~/.rustup/toolchains"
          "~/.lmstudio/extensions"
        ];
        example = [ "~/some-vm-disks" ];
        description = ''
          要排除出 Time Machine 的目录，`~/` 前缀在激活时展开为 $HOME。
          路径不存在时跳过（不代建目录）；实际排除靠目录上的 sticky xattr。

          只增不减：从本列表里删掉一条不会撤销已经打上的标记，要用
          `tmutil removeexclusion <路径>` 手动清掉。

          系统级路径（/Applications、/Users/Shared/... 等）不在本选项范围内，
          它们仍由系统设置写入的 SkipPaths 管理。
        '';
      };

      config.assertions = [
        {
          assertion = lib.all (
            path: lib.hasPrefix "/" path || lib.hasPrefix "~/" path
          ) config.shelken.darwin.timeMachine.excludePaths;
          message = "shelken.darwin.timeMachine.excludePaths 只接受绝对路径或以 ~/ 开头的路径";
        }
      ];
    };

  # 实测同一台机器上 xattr -p 约 35ms，而 tmutil addexclusion 每个路径 1~11 秒（视 TM 守护进程状态），
  # 所以不能每次激活都无条件调用：全部已排除时整个片段 0.06 秒，新排除一个目录才付一次秒级代价。
  # 标记是目录上的 xattr，目录被删掉重建后一并消失，所以每次激活都要重放一遍。
  flake.modules.homeManager.time-machine =
    {
      config,
      lib,
      osConfig,
      ...
    }:
    let
      expandHome =
        path:
        if lib.hasPrefix "~/" path then
          "${config.home.homeDirectory}/${lib.removePrefix "~/" path}"
        else
          path;

      paths = map expandHome osConfig.shelken.darwin.timeMachine.excludePaths;

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
