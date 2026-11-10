# rime

鼠须管（Squirrel）加雾凇拼音，只启用小鹤双拼

## 组成

- 上游配置与词库：flake 输入 `rime-main`（iDvel/rime-ice），由 renovate 更新
- `custom/`：对上游的三个补丁，各自的作用见文件内注释
- 链接规则与激活钩子：`_module.nix`
- 不受管理的文件：`~/Library/Rime` 下的用户词典 `*.userdb`、`installation.yaml`、`user.yaml`、`build/`，由 rime 自己读写

## 修改配置

1. 改 `custom/` 下的文件
2. 在仓库根目录运行检查，输出 `PASS` 再继续

   ```bash
   ./modules/features/input/rime/check.sh . "$(scutil --get LocalHostName)"
   ```

3. 运行 `just hm`，激活时会自动重新部署

开启 `shelken.dotfiles.liveEdit` 的主机上 `custom/` 是指向仓库的软链，改完按 `Ctrl+Option+反引号` 重新部署即可，不需要 `just hm`

`check.sh` 在临时目录里用 librime 真实编译一次将要部署的配置，不读写 `~/Library/Rime`，也不启动鼠须管

## 激活时为什么删 build 里的 yaml

rime 用源文件的修改时间判断配置要不要重新编译。Nix store 里的文件修改时间恒为 1，rime 会一直认为配置没变，`build/` 里编译好的 yaml 就停在旧版本

`_module.nix` 的 `rimeRedeploy` 给上游版本和 `custom/` 的内容算一个指纹，存在 `build/.nix-source-stamp`。指纹变化时删掉 `build/*.yaml` 并让鼠须管重新部署，词库的 `.bin` 按校验和判断，不受影响

## 排查

- 改了配置没生效 → 比较 `~/Library/Rime/build/<名>.yaml` 与源文件；删掉 `~/Library/Rime/build/*.yaml` 后重新部署
- 部署报错 → 看 `$TMPDIR/rime.squirrel/` 下的日志
- 想启用别的方案 → 改 `custom/default.custom.yaml` 的 `schema_list`
