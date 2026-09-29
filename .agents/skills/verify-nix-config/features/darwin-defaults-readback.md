# Darwin defaults readback

Darwin defaults readback 从已构建的系统产物里取出真实写入清单，逐项回读系统存储，证明声明值确实落到磁盘，而不是只证明构建成功

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
- 当前机器已应用目标系统，且 `current-system` 与 `darwinConfigurations.<host>` 指向同一结果

- **运行真实入口。** 执行 `VERIFY_HOST=<host> ./.agents/skills/verify-nix-config/scripts/verify.sh defaults`。退出码为 `0`，`transcript.log` 末行给出各项计数
- **读取结果。** `defaults-readback.json` 的 `summary.counts` 与 `entries` 记录每项的 `expected`、`actual` 与 `status`
- **区分状态。** `mismatch` 是值不符，`missing` 是声明的键在存储中不存在，`type_differs` 是值相等但类型不同；前两者为失败，`type_differs` 需消费端确认
- **确认只读。** 回读只调用 `defaults export` 与 `defaults read`，不写入偏好，也不改变 profile 链接

## Gotchas

- 清单来自构建产物而非配置源码，`current-system` 早于待验证构建时，回读到的是旧清单
- 声明类型与存储类型是两件事：布尔声明可能仍以整数 `0/1` 存储，值相等不代表已有存储被转换，需要消费端读取确认
- `type_differs` 不是失败而是提示；把它当错误会误判合法的布尔声明
- 回读只证明存储层；界面与应用行为必须通过消费该偏好的原生 API 或观察实际行为确认
- 系统级域需要读取权限，权限不足时记 `unreadable` 并单独处理，不与值不符混为一谈
