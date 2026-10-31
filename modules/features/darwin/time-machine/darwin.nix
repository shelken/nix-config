# Time Machine 排除：选项在此声明，打标记在 home.nix（用户态 xattr，不需要 Full Disk Access）
#
# 为什么不用 SkipPaths：它存在 /Library/Preferences/com.apple.TimeMachine.plist，`tmutil addexclusion -p`
# 实测无 root 时报 "requires root privileges"（exit 80），有 root 时还要求 Full Disk Access；
# 而激活脚本从终端跑（`just sw`），终端没有该权限，`-p` 这条路走不通。
# 改用 `tmutil addexclusion <路径>`（不带 -p）：只给目标打 sticky xattr
# com.apple.metadata:com_apple_backup_excludeItem，普通用户权限即可，不需要授权。
# 现有 SkipPaths 条目保持原样，不由本功能接管。
#
# 可选功能：要用的主机在 imports 里加 self.modules.darwin.time-machine
{ lib, ... }:
{
  flake.modules.darwin.time-machine =
    { config, ... }:
    {
      options.shelken.darwin.timeMachine.excludePaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        # 默认值 = 可重建的缓存 + 虚拟机磁盘所在目录：又大又常变，进备份只会拖慢并钉住本地快照。
        # 主机要额外排除别的目录时直接给这个选项赋值（列表会与本默认值合并）。
        default = [
          # 虚拟机磁盘：只增不缩的稀疏文件，每次备份都要重新扫描
          "~/.local/state/linux-builder"
          "~/Data/sandboxes"
          "~/.lima"
          "~/.orbstack"
          "~/Parallels"
          "~/Library/Containers/com.utmapp.UTM"
          "~/Library/Containers/com.isaacmarovitz.Whisky"
          # 可重建的缓存
          "~/.cache"
          "~/.vscode"
          "~/Library/Developer"
          "~/go/pkg/mod"
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

      # 相对路径会在激活脚本里相对当前工作目录解析，静默排除掉别的东西，这里挡住
      config.assertions = [
        {
          assertion = lib.all (
            path: lib.hasPrefix "/" path || lib.hasPrefix "~/" path
          ) config.shelken.darwin.timeMachine.excludePaths;
          message = "shelken.darwin.timeMachine.excludePaths 只接受绝对路径或以 ~/ 开头的路径";
        }
      ];
    };
}
