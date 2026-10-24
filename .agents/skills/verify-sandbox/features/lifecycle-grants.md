# 生命周期与授权

用户改能力上限、删除主 VM、在项目里申请额外能力时，沙箱按规则重建或拒绝，运行中的 Agent 不被意外打断

## Sub-features

- `ceil-busy` 上限变了且有上下文在运行：新启动报错，运行中的不受影响
- `ceil-idle` 上限变了且空闲：下次启动自动重建，数据卷保留
- `rm-busy` 有上下文时 `sb rm` 拒绝
- `rm-force` `sb rm --force` 强制删除并打断上下文
- `host-stubs` 上下文内 `sb`、`just`、`spawn-subagent`、`computer-use` 被拒绝并说明原因
- `grant-network` `.sandbox.yaml` 申请超出上限的私网目标时启动报错
- `grant-default` `sb.yaml` 的 `default_grant` 对所有上下文生效，同机其他端口仍拦截
- `import-target` `.sandbox.yaml` 的 `imports` 把宿主文件放到上下文内的 `target`：内容一致、可原子改名、改动不写回宿主、退出后 guest 内无残留
- `import-reject` `src` 不在 `import_sources` 内、`target` 位于家目录或根目录直下、`target` 在保留位置时，启动报错
- `plan` `sb plan` 不创建 VM 就列出当前项目解析后的挂载、导入、私网目标；`.sandbox.yaml` 超出上限时同样报错

## How to get to it (user POV)

- 编辑 `sb.yaml` 后再运行 `omp-sb`
- 运行 `sb rm`、`sb rm --force`
- 在项目根写 `.sandbox.yaml`

## Driving it with verify.sh

Preconditions:

- 主 VM Running；`$WORK` 由 `$V paths` 给出

- **忙时改上限。** 运行 `$V sb run bash -c 'sleep 25; echo LONG_DONE' > "$EVIDENCE/long.out" 2>&1 &`，3 秒后把 `$WORK/sb.yaml` 的 `cpus: 4` 改为 `cpus: 2`，运行 `$V run ceil-busy -- $V sb run true`。`rc` 为 `1`，stderr 含「sb.yaml 已变，主 VM 有 1 个执行上下文在运行」；等待后 `long.out` 含 `LONG_DONE`
- **空闲重建。** 运行 `$V run ceil-idle -- $V sb run true` 与 `$V sb status`。stderr 含「正在重建 (保留数据盘 …)」，status 显示 `cpus=2`、`consistent`；`$V msb exec sb-main -- ls /data/xdg/data/omp/agent.db` 仍存在。结束后把 `cpus` 改回 4
- **rm 忙时。** 后台运行 `$V sb run sleep 20 > "$EVIDENCE/bg.out" 2>&1 &`，5 秒后先 `$V sb status` 确认 `busy`，再运行 `$V run rm-busy -- $V sb rm`。`rc` 为 `1`，提示用 `--force`，VM 仍为 Running
- **rm 强制。** 同样准备一个后台上下文，运行 `$V run rm-force -- $V sb rm --force`。`rc` 为 `0`，后台任务以非零码退出，status 为 `Not created`
- **宿主命令桩。** 运行 `$V run stubs -- $V sb run bash -c 'for c in sb just spawn-subagent computer-use; do $c status; echo "$c rc=$?"; done'`。四个命令都是 `rc=1` 且给出原因
- **默认放行。** 测试项目无 `.sandbox.yaml` 时运行 `$V run grant -- $V sb run bash -c 'curl -s -o /dev/null -m 5 -w "%{http_code}\n" https://cpa.int.ooooo.space/v1/models; curl -s -o /dev/null -m 5 -w "%{http_code}\n" http://192.168.69.46:80'`。第一行 `401`，第二行 `000`（宿主上同一地址返回 301）
- **超出上限。** 在测试项目写 `network: ["192.168.69.60"]` 到 `.sandbox.yaml`，运行 `$V run grant-over -- $V sb run true`。`rc` 为 `1`，stderr 含「超出能力上限」；结束后删除该文件
- **导入到目标路径。** 运行 `echo fake-kubeconfig > ~/.kube/sb-verify.yaml; shasum ~/.kube/sb-verify.yaml`，在测试项目写 `.sandbox.yaml`：`imports: [{src: ~/.kube/sb-verify.yaml, target: ~/.kube/sb-verify.yaml}]`。运行 `$V run import-target -- $V sb run bash -c 'cat ~/.kube/sb-verify.yaml; ls ~/.kube; stat -c "%a" ~/.kube/sb-verify.yaml; mv ~/.kube/sb-verify.yaml ~/.kube/t && mv ~/.kube/t ~/.kube/sb-verify.yaml && echo RENAME_OK; echo changed >> ~/.kube/sb-verify.yaml'`。输出依次为 `fake-kubeconfig`、只有 `sb-verify.yaml` 一项、`600`、`RENAME_OK`，`rc` 为 `0`；宿主文件的 `shasum` 不变；`$V msb exec sb-main -- ls /run/sandbox/contexts` 为空。结束后删除 `~/.kube/sb-verify.yaml` 与 `.sandbox.yaml`
- **导入被拒绝。** 分别把 `.sandbox.yaml` 的 imports 写成 `src: /etc/hosts`（`target: ~/.kube/h`）、`target: ~/h`、`target: /etc/foo/h`（`src` 用上一条的文件），各运行一次 `$V run import-reject-<n> -- $V sb run true`。`rc` 都为 `1`，stderr 依次含「超出能力上限」、「位于某个子目录内」、「沙箱保留位置」；结束后删除 `.sandbox.yaml`
- **查看授权。** 测试项目写 `.sandbox.yaml`：`imports: [{src: ~/.kube/sb-verify.yaml, target: ~/.kube/sb-verify.yaml}]`，先 `echo x > ~/.kube/sb-verify.yaml`，运行 `$V run plan -- $V sb plan`。`rc` 为 `0`，stdout 含「导入文件」下的 `→ ~/.kube/sb-verify.yaml` 与默认放行的 `192.168.69.46:443（sb.yaml 默认放行）`；把 `src` 改成 `/etc/hosts` 再运行 `$V run plan-over -- $V sb plan`，`rc` 为 `1` 且 stderr 含「超出能力上限」。结束后删除 `.sandbox.yaml` 与该文件

## Gotchas

- 修改的是 `$WORK/sb.yaml`，不是仓库里的 `sb.yaml`
- `default_grant` 不进 VM 配置，修改它不会改变指纹，也不触发重建
- `sb rm` 前务必确认后台上下文确实启动了（`sb status` 为 busy），否则会误判为「忙时没有拒绝」
