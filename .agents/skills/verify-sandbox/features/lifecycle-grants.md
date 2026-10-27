# 生命周期与授权

用户改能力上限、删除主 VM、在项目里申请额外能力时，沙箱按规则重建或拒绝，运行中的 Agent 不被意外打断

## Sub-features

- `ceil-busy` 上限变了且有上下文在运行：新启动报错，运行中的不受影响
- `ceil-idle` 上限变了且空闲：下次启动自动重建，数据卷保留
- `rm-busy` 有上下文时 `sb rm` 拒绝
- `rm-force` `sb rm --force` 强制删除并打断上下文
- `host-stubs` 上下文内 `sb`、`just`、`spawn-subagent`、`computer-use` 被拒绝并说明原因
- `trust-required` `.sandbox.yaml` 未批准或批准后内容变了：启动直接报错并提示 `sb trust`，改注释或格式不失效
- `trust-network` 批准后项目声明的私网目标可达，未声明的同机其他端口仍拦截
- `grant-default` `sb.yaml` 的 `default_grant` 对所有上下文生效，同机其他端口仍拦截
- `import-target` `.sandbox.yaml` 的 `imports` 把宿主文件放到上下文内的 `target`：内容一致、可原子改名、改动不写回宿主、退出后 guest 内无残留
- `import-reject` `target` 位于家目录或根目录直下、`target` 在保留位置、`src` 不存在时，启动报错
- `plan` `sb plan` 不创建 VM 就列出当前项目解析后的挂载、导入、私网目标与批准状态；`.sandbox.yaml` 写法不合规时同样报错

## How to get to it (user POV)

- 编辑 `sb.yaml` 后再运行 `omp-sb`
- 运行 `sb rm`、`sb rm --force`
- 在项目根写 `.sandbox.yaml`

## Driving it with verify.sh

Preconditions:

- 主 VM Running；先 `eval "$($V paths)"` 与 `eval "$($V env)"`，再定义 `IP=${GATEWAY_ADDR%:*}` 与等待忙碌的函数：`wait_busy() { for _ in $(seq 30); do $V sb status 2>&1 | grep -q busy && return; sleep 1; done; return 1; }`
- 宿主上 `curl -s -o /dev/null -m 5 -w '%{http_code}' http://$IP:80` 有 HTTP 响应（不是 `000`），否则「默认放行」「批准流程」两步看不出放行与拦截的差别

- **忙时改上限。** 运行 `$V sb run bash -c 'sleep 25; echo LONG_DONE' > "$EVIDENCE/long.out" 2>&1 &`，`wait_busy` 返回后把 `$WORK/sb.yaml` 的 `cpus` 改为 `$((CPUS - 1))`，运行 `$V run ceil-busy -- $V sb run true`。`rc` 为 `1`，stderr 含「sb.yaml 已变，主 VM 有 1 个执行上下文在运行」；等待后 `long.out` 含 `LONG_DONE`
- **空闲重建。** 运行 `$V run ceil-idle -- $V sb run true` 与 `$V sb status`。stderr 含「正在重建 (保留数据盘 …)」，status 显示 `cpus=$((CPUS - 1))`、`consistent`；`$V msb exec sb-main -- ls /data/xdg/data/omp/agent.db` 仍存在。结束后把 `cpus` 改回 `$CPUS`
- **rm 忙时。** 后台运行 `$V sb run sleep 40 > "$EVIDENCE/bg.out" 2>&1 &`，`wait_busy` 返回后再运行 `$V run rm-busy -- $V sb rm`。`rc` 为 `1`，提示用 `--force`，VM 仍为 Running
- **rm 强制。** 同样后台启动一个上下文并记下 `pid=$!`，`wait_busy` 返回后运行 `$V run rm-force -- $V sb rm --force`。`rc` 为 `0`，`wait $pid` 返回非零，status 为 `Not created`；下一步前先 `$V sb up`
- **宿主命令桩。** 运行 `$V run stubs -- $V sb run bash -c 'for c in sb just spawn-subagent computer-use; do $c status; echo "$c rc=$?"; done'`。`stubs.out` 里四个命令都是 `rc=1`，原因（「沙箱内…」之类）也写在 stdout，因为桩脚本用 `echo` 输出；`stubs.err` 除 `[sb]` 行外为空
- **默认放行。** 测试项目无 `.sandbox.yaml` 时运行 `$V run grant -- $V sb run bash -c "curl -s -o /dev/null -m 5 -w '%{http_code}\n' $GATEWAY_URL/models; curl -s -o /dev/null -m 5 -w '%{http_code}\n' http://$IP:80"`。第一行是 HTTP 状态码（默认放行的 `$GATEWAY_ADDR`），第二行 `000`（同一台机器的其他端口被拦截，宿主上它有响应）
- **批准流程。** 在测试项目写 `network: ["$IP:80"]` 到 `.sandbox.yaml`。运行 `$V run trust-none -- $V sb run true`：`rc` 为 `1`，stderr 含「未批准」；`$V sb plan` 最后一行含「未批准」。运行 `$V sb trust`，再运行 `$V run trust-net -- $V sb run bash -c "curl -s -o /dev/null -m 5 -w '%{http_code}\n' http://$IP:80; curl -s -o /dev/null -m 5 -w '%{http_code}\n' http://$IP:8080"`：第一行是 HTTP 状态码，第二行 `000`。在文件里只加一行注释，`$V run trust-comment -- $V sb run true` 仍然 `rc` 为 `0`；把端口改成 `8080`，`$V run trust-changed -- $V sb run true` 又变成 `rc` 为 `1`。结束后删除该文件；批准记录在隔离的 `$WORK/msb/approvals`，随 `cleanup` 删除
- **导入到目标路径。** 运行 `echo fake-kubeconfig > ~/.kube/sb-verify.yaml; shasum ~/.kube/sb-verify.yaml`，在测试项目写 `.sandbox.yaml`：`imports: [{src: ~/.kube/sb-verify.yaml, target: ~/.kube/sb-verify.yaml}]`，运行 `$V sb trust`。再运行 `$V run import-target -- $V sb run bash -c 'cat ~/.kube/sb-verify.yaml; ls ~/.kube; stat -c "%a" ~/.kube/sb-verify.yaml; mv ~/.kube/sb-verify.yaml ~/.kube/t && mv ~/.kube/t ~/.kube/sb-verify.yaml && echo RENAME_OK; echo changed >> ~/.kube/sb-verify.yaml'`。输出依次为 `fake-kubeconfig`、只有 `sb-verify.yaml` 一项（目标目录被暂存目录遮住，宿主 `~/.kube` 里其他文件在上下文内不可见）、`600`、`RENAME_OK`，`rc` 为 `0`；宿主文件的 `shasum` 不变；`$V msb exec sb-main -- ls -A /run/sandbox/contexts` 只有 `.slot.lock`。结束后删除 `~/.kube/sb-verify.yaml` 与 `.sandbox.yaml`
- **导入被拒绝。** 先 `echo x > ~/.kube/sb-verify.yaml`，再分别把 `.sandbox.yaml` 的 imports 写成 `target: ~/h`（`src` 用该文件）、`src: ~/.kube/不存在的文件`（`target: ~/.kube/x`）、`target: /etc/foo/h`（`src` 用该文件），各运行一次 `$V run import-reject-<n> -- $V sb run true`。`rc` 都为 `1`，stderr 依次含「位于某个子目录内」、「导入文件不存在」、「沙箱保留位置」。前两个写法错误在批准检查之前报出；保留位置由 launcher 检查，第三个要先 `$V sb trust` 才会走到。结束后删除 `.sandbox.yaml` 与该文件
- **查看授权。** 先 `echo x > ~/.kube/sb-verify.yaml`，测试项目写 `.sandbox.yaml`：`imports: [{src: ~/.kube/sb-verify.yaml, target: ~/.kube/sb-verify.yaml}]` 与 `network: ["$IP:80"]`（内容与上面各步批准过的都不同），运行 `$V run plan -- $V sb plan`。`rc` 为 `0`，stdout 含「导入文件」下的 `→ ~/.kube/sb-verify.yaml`、`$GATEWAY_ADDR（sb.yaml 默认放行）`、`$IP:80（项目声明）` 与「批准状态: 未批准」；`$V sb trust` 后再运行显示「批准状态: 已批准」；把 `target` 改成 `~/h` 运行 `$V run plan-bad -- $V sb plan`，`rc` 为 `1`。结束后删除 `.sandbox.yaml` 与该文件

## Gotchas

- 修改的是 `$WORK/sb.yaml`，不是仓库里的 `sb.yaml`
- `default_grant` 不进 VM 配置，修改它不会改变指纹，也不触发重建
- `sb rm` 前务必确认后台上下文确实启动了（`sb status` 为 busy），否则会误判为「忙时没有拒绝」
