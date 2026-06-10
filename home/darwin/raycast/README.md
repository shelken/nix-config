# 自动化导出导入Raycast配置

> 需要开启secret `config.shelken.secrets.enable = true` 才会有rayconfig文件

> 导出导入前先把密码export

```shell
# 前面带有空格防止历史记录
 export RAYCAST_SETTINGS_PASSWORD=xxxxx
```

## 导出

```shell
just raycast-export <output_dir>
```

命令将使用 osascript 操作 GUI 界面，将配置导出到指定目录。

## 导入

```shell
just raycast-import
```

命令将从目录 `~/.config/raycast` 导入最新的 Raycast 配置。
