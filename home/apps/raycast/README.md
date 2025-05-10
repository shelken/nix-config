# 自动化导出导入Raycast配置

> 导出导入前先把密码export

```shell
# 前面带有空格防止历史记录
 export RAYCAST_SETTINGS_PASSWORD=xxxxx
```

## 导出

```shell
just raycast-export
```

命令将使用osascript操作gui界面将配置导出到目录`home/apps/raycast/`目录下

## 导入

```shell
just raycast-import
```

命令将从目录`home/apps/raycast`导入最新的raycast配置
