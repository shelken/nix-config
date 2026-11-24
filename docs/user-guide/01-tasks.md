# 声明式定时任务

所有字段定义与默认值见 [lib/tasks.nix](../../lib/tasks.nix)，设计约束与 `mise.toml` 项目写法见 [tasks README](../../modules/features/system/tasks/README.md)

## 加一个机器专属任务

1. 新建 `hosts/<机器>/tasks/<名>.nix`，文件名去掉 `.nix` 即为任务名：

```nix
{ pkgs, ... }:
{
  when = "3:15";
  packages = with pkgs; [
    curl
  ];
  script = ''
    curl --fail --silent https://example.com/health >/dev/null
  '';
}
```

2. 执行 `git add hosts/<机器>/tasks/<名>.nix`，再运行 `just sw`
3. 运行 `ntask ls` 确认任务已注册

## 在模块里声明任务

在任意模块的 `shelken.tasks.<名>` 中声明：

```nix
shelken.tasks.kopia-backup = {
  when = [ "6:39" "18:39" ];
  jitter = 600;
  packages = [ pkgs.kopia ];
  script = "kopia snapshot create $HOME/Code";
};
```

临时停用任务时加 `enable = false` 再重新应用；root 任务（`user = false`）须写在机器 `tasks/` 目录或功能的 darwin 模块中，不得写在 Home Manager 模块里

## 命令

```bash
ntask ls            # 查看所有已部署任务状态
ntask log <名>      # 查看最近一次日志（支持 -n N、-f、--all）
ntask run <名>      # 按 launchd 隔离环境前台执行并写日志
ntask info <名>     # 查看调度、日志与 plist 路径
```

完整子命令与参数运行 `ntask help -v` 查看
