# Darwin defaults readback

Darwin defaults readback 从本机已应用的系统产物（`/run/current-system/activate`，缺失时才退回当前 flake 的 toplevel）里取出真实写入清单，逐项回读系统存储，证明声明值确实落到磁盘，而不是只证明构建成功

## Sub-features

- `defaults-readback-doctor` 确认当前 host 与 Home 同源不变量
- `defaults-readback-source` 从 `activate` 脚本解析实际写入，不做配置重新推导
- `defaults-readback-compare` 逐项比对值与存储类型，区分值漂移与类型差异
- `defaults-readback-domains` 覆盖标准选项、自定义域和路径形式的系统域
- `defaults-readback-no-switch` 只读系统存储与 Nix store，不修改任何偏好

## How to get to it (user POV)

- 在仓库根目录运行 `./.agents/skills/verify-nix-config/scripts/verify.sh defaults`
- 只想查看单个域的当前值时用 `defaults read <domain> <key>`

## Driving it with Bash

Preconditions:

- helper 内置 doctor；门禁失败时不执行回读
- 当前机器已应用目标系统。doctor 不检查 `current-system` 与 `darwinConfigurations.<host>` 是否同一结果，回读到的是已应用系统的清单；两者不同时结论只覆盖已应用的部分。核对：`readlink /run/current-system` 与 `nix eval --raw .#darwinConfigurations.<host>.config.system.build.toplevel.outPath` 的最后一段是否相同

- **运行真实入口。** 执行 `VERIFY_HOST=<host> ./.agents/skills/verify-nix-config/scripts/verify.sh defaults`。退出码为 `0`，stdout 末两行是 `match=<n> type_differs=<n> mismatch=<n> missing=<n> unreadable=<n>` 与 `evidence=<dir>`
- **读取结果。** `<evidence>/defaults-readback.json` 的 `summary` 含 `activate`（读的是哪份脚本）、`total` 与 `counts`（数量为零的状态不出现），`entries` 逐项记录 `domain`、`key`、`expected`、`actual` 与 `status`；`transcript.log` 为每个 `type_differs`、`mismatch`、`missing`、`unreadable` 的键各列一行，`match` 不列
- **区分状态。** `mismatch` 是值不符，`missing` 是声明的键在存储中不存在，`unreadable` 是回读本身失败，`type_differs` 是值相等但类型不同；前三者计入失败，退出码为 `1`，`type_differs` 不计入失败，需消费端确认
- **确认只读。** 回读只调用 `defaults export`，不写入偏好，也不改变 profile 链接

## Gotchas

- 清单来自构建产物而非配置源码，`current-system` 早于待验证构建时，回读到的是旧清单
- 声明类型与存储类型是两件事：布尔声明可能仍以整数 `0/1` 存储，值相等不代表已有存储被转换，需要消费端读取确认
- `type_differs` 不是失败而是提示；把它当错误会误判合法的布尔声明
- 回读只证明存储层；界面与应用行为必须通过消费该偏好的原生 API 或观察实际行为确认
- 系统级域需要读取权限。权限不足时 `defaults export` 仍返回 `0` 与近乎空的 plist，所以会被记为 `missing` 而不是 `unreadable`；`unreadable` 只在命令非零退出或 plist 解析失败时出现，两者都计入失败
- `~<user>/Library/Preferences/ByHost/...` 这类 `~` 形式的域无法被 `defaults export` 解析，会得到空结果；本仓库目前没有这类域，将来出现时先改成绝对路径
- 写入清单靠正则匹配 `defaults write <域> <键> '<plist>'`，该格式由 nix-darwin 生成；升级 nix-darwin 后若写法变化，漏抓的项不会报错，核对 `total` 是否合理
