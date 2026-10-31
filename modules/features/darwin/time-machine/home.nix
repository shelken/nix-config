# 激活时给列出的目录打 Time Machine 排除标记（选项值来自 darwin 侧的 osConfig）
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
    in
    lib.mkIf (paths != [ ]) {
      home.activation.timeMachineExclusions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        excludeFromBackup() {
          _tm_path="$1"
          if [ ! -e "$_tm_path" ]; then
            echo "time-machine: 跳过不存在的路径 $_tm_path"
          elif /usr/bin/xattr -p com.apple.metadata:com_apple_backup_excludeItem "$_tm_path" > /dev/null 2>&1; then
            echo "time-machine: 已排除 $_tm_path"
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
    };
}
