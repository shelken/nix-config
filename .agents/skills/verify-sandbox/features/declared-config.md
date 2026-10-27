# 声明配置只读、运行状态可写

上下文里 `~/.omp/agent`、`~/.pi/agent`、`~/.agents` 整体可写，落在数据卷、所有上下文共用；Nix 声明的路径逐项只读，插件改不了、删不掉、也绕不过去

## Sub-features

- `decl-ro` 声明文件 `rm`、`mv`、`>` 写入、`touch` 全部失败；声明目录内不能新建文件
- `decl-sibling` 声明路径的兄弟可写，另开上下文能读到，退出再开仍在
- `decl-mixed` `extensions/` 里声明文件只读，新增文件可写
- `decl-xdg` `.config/<X>` 声明配置在 `$XDG_CONFIG_HOME/<X>`，只读
- `decl-ancestor` 嵌套声明项的祖先目录（`extensions/`、`intercom/`、`/data/xdg/config/<X>`、`~/.pi`、`~`）改名失败，声明文件不会消失。只对挂载点成立：可写根本身经数据卷上的 `/data/home/.pi` 仍可改名，这是已知局限
- `decl-state` 不设环境变量时 pi-fff 在 `~/.pi/agent/fff` 有数据目录，`~/.pi/agent/intercom` 运行目录存在且可写
- `decl-placeholder` 声明路径上残留了类型不符的空占位：没有别的上下文时自动清掉并正常启动；有别的上下文时报错并给出路径与上下文数；非空内容一律报错
- `decl-roots` 可写根来自发布目录的 `writable-roots`：清单缺失直接拒绝启动；改变清单（增删根）就改变 tmpfs 挂载点与 `imports` 保留位置，launcher 里没有第二份根清单

## How to get to it (user POV)

- 在沙箱里运行 pi 或 OMP，插件照常写自己的数据库与设置；`just hm` 后重开上下文读到新配置

## Driving it with verify.sh

Preconditions:

- 先 `eval "$($V paths)"` 与 `eval "$($V env)"`
- `$V sb status` 显示「VM 状态: Running」与「上限一致: consistent」。VM 停止时指纹同样一致，只看后者不够

- **声明文件只读。** 运行 `$V run decl-ro -- $V sb run bash -c 'f=~/.pi/agent/settings.json; rm -f $f; mv $f ~/.pi/agent/x; echo x > $f; touch $f; touch ~/.pi/agent/agents/new.md; head -c1 $f'`。stderr 依次含两次 `Device or resource busy`、三次 `Read-only file system`，最后输出 `{`
- **兄弟可写、共用、持久。** 运行 `$V run decl-sibling-w -- $V sb run bash -c 'echo hi > ~/.pi/agent/sibling-check.txt'`，再运行 `$V run decl-sibling-r -- $V sb run bash -c 'cat ~/.pi/agent/sibling-check.txt'`（`~` 必须在 `bash -c` 里展开，否则宿主 shell 会把它换成宿主的家目录）。第二个输出 `hi`。结束后删掉该文件
- **extensions 混合。** 运行 `$V run decl-mixed -- $V sb run bash -c 'echo y >> ~/.omp/agent/extensions/guard.ts; echo "//x" > ~/.omp/agent/extensions/mine.ts && echo NEW_OK; rm ~/.omp/agent/extensions/mine.ts'`。stderr 含 `Read-only file system`，stdout 含 `NEW_OK`
- **XDG 配置。** 运行 `$V run decl-xdg -- $V sb run bash -c 'cat $XDG_CONFIG_HOME/ponytail/config.json; touch $XDG_CONFIG_HOME/ponytail/config.json'`。输出 ponytail 的 JSON，stderr 含 `Read-only file system`
- **祖先不能改名。** 运行 `$V run decl-ancestor -- $V sb run bash -c 'for d in ~/.omp/agent/extensions ~/.pi/agent/intercom $XDG_CONFIG_HOME/ponytail ~/.pi ~/.omp ~ /data/home/.omp/agent/extensions /data/home/.pi/agent/intercom; do mv $d $d.bak; done; ls ~/.omp/agent/extensions/guard.ts ~/.pi/agent/intercom/config.json'`。`decl-ancestor.err` 含八次 `Device or resource busy`，`decl-ancestor.out` 里两个声明文件都在
- **可写根本身可改名。** 运行 `$V run decl-root-fallback -- $V sb run bash -c 'mv /data/home/.pi /data/home/.pi.bak && echo RENAMED; ls -d /data/home/.pi*; mv /data/home/.pi.bak /data/home/.pi'`。输出 `RENAMED` 与 `/data/home/.pi.bak`。这是 README 记录的已知局限，不是回归
- **运行状态。** 运行 `$V run decl-state -- $V sb run bash -c 'env | grep -c ^FFF_; timeout 120 omp --model="$0" -p "只回复 OK"; ls -d ~/.pi/agent/fff ~/.pi/agent/intercom' "$MODEL"`。第一行 `0`，OMP 正常回复，`fff` 与 intercom 运行目录存在（两个插件由 OMP 加载；`fff` 里的文件名由插件决定，不检查）
- **残留占位预检。** 设 `P=/data/home/.pi/agent/themes/catppuccin.json`，按顺序：
  - 有别的上下文时报错不删：后台起 `$V sb run sleep 25`，5 秒后 `$V msb exec sb-main -- bash -c "rm $P; mkdir $P"`，运行 `$V run decl-placeholder-busy -- $V sb run true`。`rc` 为 `1`，stderr 含 `$P` 与「还有 1 个上下文在运行」。占位要在后台上下文启动之后再造，否则它自己的预检会先清掉
  - 非空内容报错：等后台上下文退出，`$V msb exec sb-main -- bash -c "echo keep > $P/user.txt"`，运行 `$V run decl-placeholder-full -- $V sb run true`。`rc` 为 `1`，stderr 含「不会自动删除」
  - 空占位自动清掉：`$V msb exec sb-main -- rm $P/user.txt`，运行 `$V run decl-placeholder-clean -- $V sb run head -c 12 ~/.pi/agent/themes/catppuccin.json`。`rc` 为 `0`，输出主题 JSON 开头
- **声明源缺失。** 设 `V1=$(readlink "$WORK/sbcfg/current")`。宿主侧把 `$WORK/sbcfg/$V1/.pi/agent/pi-fff.json` 临时改名，等 guest 看到变化（`$V msb exec sb-main -- test ! -e /run/sandbox-config/$V1/.pi/agent/pi-fff.json` 返回 0；宿主改动在 guest 里要稍等才可见，不等会得到假的通过），运行 `$V run decl-missing-src -- $V sb run true`，再改回。`rc` 为 `1`，stderr 含「声明配置缺失」与该文件在 `/run/sandbox-config/<版本>/` 下的路径
- **清单缺失。** 对 `declared-paths` 与 `writable-roots` 各做一次：宿主侧把 `$WORK/sbcfg/$V1/<清单>` 临时改名，同样等 guest 看不到它，运行 `$V run decl-missing-list -- $V sb run bash -c 'echo CONTEXT_STARTED'`，再改回。`rc` 为 `1`，stdout 不含 `CONTEXT_STARTED`，stderr 含「发布目录缺少清单：」与 `/run/sandbox-config/<版本>/` 下对应文件的路径；该文件为空的话 `rc` 为 `0` 才是漂移。`e2e/smoke.sh` 的一次性 VM 带有空清单的发布目录，所以不受影响
- **imports 不能落在根上。** 先 `echo x > ~/.kube/sb-verify.yaml`。对 `target: ~/.pi/agent/x`（落在根下）和 `target: ~/.omp/x`（落在根的上层挂载点下）各做一次：在 `.sandbox.yaml` 写 `imports: [{src: ~/.kube/sb-verify.yaml, target: <目标>}]`，运行 `$V sb trust`，再运行 `$V run decl-imports-<root|upper> -- $V sb run true`。`rc` 都为 `1`，stderr 含「是沙箱保留位置」。不先 `sb trust` 会先报「未批准」，`src` 不存在会先报「导入文件不存在」。结束后删除 `.sandbox.yaml` 与该文件

## Gotchas

- `msb exec` 在上下文外，看到的 `/root/.pi/agent` 是指向只读发布目录的符号链接，不是可写根；检查运行状态要走 `sb run`
- 数据卷上的可写根在 `/data/home/`，上下文里通过 `/data/home/...` 也能看到同一份运行状态
- 占位预检只在启动时做；运行中的上下文看到的是启动时的声明配置快照
- 上下文里命令的 stdout 进 `.out`、stderr 进 `.err`；宿主命令桩例外，它们用 `echo` 把原因写进 stdout
