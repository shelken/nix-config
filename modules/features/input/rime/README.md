# rime

鼠须管（Squirrel）加雾凇拼音，只启用小鹤双拼

## 修改与验证

1. 改 `custom/` 下的文件
2. 仓库根目录运行编译检查（临时目录用 librime 真实编译，不改 `~/Library/Rime`），输出 `PASS` 再继续：`./modules/features/input/rime/check.sh . "$(scutil --get LocalHostName)"`
3. 运行 `just hm` 自动重新部署；开启 `shelken.dotfiles.liveEdit` 的主机改完直接按 `Ctrl+Option+反引号` 部署

## 同步

- 每天 4:30 由定时任务 `rime-sync` 触发（手动 `ntask run rime-sync`，日志 `ntask log rime-sync`）
- 同步目录为 `~/Documents/rime/sync`，依赖 iCloud「桌面与文稿」跨设备传递；未开启该功能的主机仅相当于本机备份
- 同步触发不返回结果，验证同步是否生效看快照修改时间：`ls -l ~/Documents/rime/sync/*/*.userdb.txt`

## 排查

- 改了配置没生效 → 比较 `~/Library/Rime/build/<名>.yaml` 与源文件，或删掉 `~/Library/Rime/build/*.yaml` 后重新部署
- 部署报错 → 看 `$TMPDIR/rime.squirrel/` 下的日志
- 启用其他方案 → 改 `custom/default.custom.yaml` 的 `schema_list`，把该方案文件加进 `default.nix` 的 `upstreamFiles`，再跑 `check.sh`
