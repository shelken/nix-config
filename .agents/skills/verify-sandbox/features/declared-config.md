# 声明配置只读、运行状态可写

上下文里 `~/.omp/agent`、`~/.pi/agent`、`~/.agents` 整体可写，落在数据卷、所有上下文共用；Nix 声明的路径逐项只读，插件改不了、删不掉、也绕不过去

## Sub-features

- `decl-ro` 声明文件 `rm`、`mv`、`>` 写入、`touch` 全部失败；声明目录内不能新建文件
- `decl-sibling` 声明路径的兄弟可写，另开上下文能读到，退出再开仍在
- `decl-mixed` `extensions/` 里声明文件只读，新增文件可写
- `decl-xdg` `.config/<X>` 声明配置在 `$XDG_CONFIG_HOME/<X>`，只读
- `decl-ancestor` 嵌套声明项的祖先目录（`extensions/`、`intercom/`、`/data/xdg/config/<X>`、`~/.pi`、`~`）改名失败，声明文件不会消失
- `decl-state` 不设环境变量时 pi-fff 在 `~/.pi/agent/fff` 建库，`~/.pi/agent/intercom` 运行目录可建
- `decl-placeholder` 声明路径上残留了类型不符的空占位：没有别的上下文时自动清掉并正常启动；有别的上下文时报错并给出路径与上下文数；非空内容一律报错
- `decl-roots` 可写根来自发布目录的 `writable-roots`：清单缺失直接拒绝启动；改变清单（增删根）就改变 tmpfs 挂载点与 `imports` 保留位置，launcher 里没有第二份根清单

## How to get to it (user POV)

- 在沙箱里运行 pi 或 OMP，插件照常写自己的数据库与设置；`just hm` 后重开上下文读到新配置

## Driving it with verify.sh

Preconditions:

- `$V sb status` 显示「上限一致: consistent」

- **声明文件只读。** 运行 `$V run decl-ro -- $V sb run bash -c 'f=~/.pi/agent/settings.json; rm -f $f; mv $f ~/.pi/agent/x; echo x > $f; touch $f; touch ~/.pi/agent/agents/new.md; head -c1 $f'`。stderr 依次含两次 `Device or resource busy`、三次 `Read-only file system`，最后输出 `{`
- **兄弟可写、共用、持久。** 运行 `$V run decl-sibling-w -- $V sb run bash -c 'echo hi > ~/.pi/agent/sibling-check.txt'`，再运行 `$V run decl-sibling-r -- $V sb run bash -c 'cat ~/.pi/agent/sibling-check.txt'`（`~` 必须在 `bash -c` 里展开，否则宿主 shell 会把它换成宿主的家目录）。第二个输出 `hi`。结束后删掉该文件
- **extensions 混合。** 运行 `$V run decl-mixed -- $V sb run bash -c 'echo y >> ~/.omp/agent/extensions/guard.ts; echo "//x" > ~/.omp/agent/extensions/mine.ts && echo NEW_OK; rm ~/.omp/agent/extensions/mine.ts'`。stderr 含 `Read-only file system`，stdout 含 `NEW_OK`
- **XDG 配置。** 运行 `$V run decl-xdg -- $V sb run bash -c 'cat $XDG_CONFIG_HOME/ponytail/config.json; touch $XDG_CONFIG_HOME/ponytail/config.json'`。输出 ponytail 的 JSON，stderr 含 `Read-only file system`
- **祖先不能改名。** 运行 `$V run decl-ancestor -- $V sb run bash -c 'for d in ~/.omp/agent/extensions ~/.pi/agent/intercom $XDG_CONFIG_HOME/ponytail ~/.pi ~/.omp ~ /data/home/.omp/agent/extensions /data/home/.pi/agent/intercom; do mv $d $d.bak; done; ls ~/.omp/agent/extensions/guard.ts ~/.pi/agent/intercom/config.json'`。每个 `mv` 都报 `Device or resource busy`，最后两个文件都在
- **运行状态。** 运行 `$V run decl-state -- $V sb run bash -c 'env | grep -c ^FFF_; timeout 120 omp --model=cpa/gpt-5.6-luna -p "只回复 OK"; ls ~/.pi/agent/fff; ls -d ~/.pi/agent/intercom'`。第一行 `0`，OMP 正常回复，`fff` 下有 `frecency`、`history`，intercom 运行目录存在（两个插件由 OMP 加载）
- **残留占位预检。** 设 `P=/data/home/.pi/agent/themes/catppuccin.json`，按顺序：
  - 有别的上下文时报错不删：后台起 `$V sb run sleep 25`，5 秒后 `$V msb exec sb-main -- bash -c "rm $P; mkdir $P"`，运行 `$V run decl-placeholder-busy -- $V sb run true`。`rc` 为 `1`，stderr 含 `$P` 与「还有 1 个上下文在运行」。占位要在后台上下文启动之后再造，否则它自己的预检会先清掉
  - 非空内容报错：等后台上下文退出，`$V msb exec sb-main -- bash -c "echo keep > $P/user.txt"`，运行 `$V run decl-placeholder-full -- $V sb run true`。`rc` 为 `1`，stderr 含「不会自动删除」
  - 空占位自动清掉：`$V msb exec sb-main -- rm $P/user.txt`，运行 `$V run decl-placeholder-clean -- $V sb run head -c 12 ~/.pi/agent/themes/catppuccin.json`。`rc` 为 `0`，输出主题 JSON 开头
- **声明源缺失。** 宿主侧把 `$WORK/sbcfg/<current 指向的版本>/.pi/agent/pi-fff.json` 临时改名，运行 `$V run decl-missing-src -- $V sb run true`，再改回。`rc` 为 `1`，stderr 含「声明配置缺失」与该文件在 `/run/sandbox-config/<版本>/` 下的路径
- **清单缺失。** 宿主侧把 `$WORK/sbcfg/<current 指向的版本>/declared-paths`（再单独对 `writable-roots` 重复一次）临时改名，运行 `$V run decl-missing-list -- $V sb run true`，再改回。`rc` 为 `1`，stderr 含「缺少清单」与 `/run/sandbox-config/<版本>/` 下对应文件的路径；没有发布目录的一次性 VM（`e2e/smoke.sh`）不受影响
- **imports 不能落在根上。** 在 `.sandbox.yaml` 里临时声明一条 `imports`，目标目录设为 `~/.pi/agent/x`（落在根下）和 `~/.omp/x`（落在根的上层挂载点下），分别运行 `$V run decl-imports-root -- $V sb run true`。`rc` 都为 `1`，stderr 含「是沙箱保留位置」

## Gotchas

- `msb exec` 在上下文外，看到的 `/root/.pi/agent` 是指向只读发布目录的符号链接，不是可写根；检查运行状态要走 `sb run`
- 数据卷上的可写根在 `/data/home/`，上下文里通过 `/data/home/...` 也能看到同一份运行状态
- 占位预检只在启动时做；运行中的上下文看到的是启动时的声明配置快照
- `pi` 在沙箱里还不能用：它在启动时按 `settings.json` 自动安装 packages，私有包的 `node-pty` 需要 `node-gyp`，guest 没有。不要用 pi 验证运行状态
