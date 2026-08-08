# session-start 规范

`session_start` 与 `model_select` 是 pi 插件在会话生命周期里最常触发网络的两个事件. 本规范定义二者共用的通用契约, 所有 provider 遵守.

## 核心契约: activate

每个 provider 提供一个 `activate(ctx, isMine)`, 两个事件共用:

```
session_start:
  会话簿记 (initSessionIds / registerSession / currentUi 缓存)   ← 仅此处
  activate(ctx, isProviderModel(ctx.model))

model_select:
  activate(ctx, isProviderModel(ctx.model))
```

**`isMine = isProviderModel(ctx.model)`** — 当前所选模型是否归本 provider 管辖.

会话簿记 (session id 注册、UI handle 缓存) 是 `session_start` 独有的、与模型无关的初始化, 留在 `session_start`, 不进 `activate`. `model_select` 不重复簿记.

## activate(ctx, isMine) 形态

```
function activate(ctx, isMine) {
  if (hasUI) { currentUi = ctx.ui; footerIsMine = isMine }   // UI 缓存
  if (!isMine) { clearStatus(ctx); return }                  // R2 模型门闩
  refreshStatus(ctx)                                          // 只读 GET, R1 非阻塞
  if (hasUI) backgroundTask(ctx).catch(log)                  // R3+R4 后台任务
}
```

三层门闩依次过滤, 任一不满足即短路, 不发网络:

```
isMine?  →  hasUI?  →  锁+幂等?
  N:清状态      N:跳后台     N:跳过
```

## UI 缓存的 stale 陷阱

`currentUi = ctx.ui` 这类缓存把 per-session `ctx` 提升到模块级. `ctx.ui` 的 getter
内部调 pi-core `runner.assertActive()`; 一旦 session 被
`ctx.newSession()` / `fork()` / `switchSession()` / `reload()` 替换, 旧 ctx 即被打
stale, 再读 `ctx.ui` 会抛 `This extension ctx is stale...`.

**安全用法**: 缓存的 `ctx`/`ctx.ui` 只在**同一事件回调内**同步消费, 回调返回后
不再持有. 事件每次都拿 fresh ctx, 天然安全.

**危险用法**: 把 `ctx.ui` 存进模块级闭包, 交给**跨事件、跨 session 的长生命周期
异步链**调用 (典型: chat/failover/refresh/后台任务里调 `notify`). 这些链可能活过
session 替换, 此时缓存的 ctx 已 stale, 一调即抛, 并沿异步链上抛搞垮主流程
(chat 被误判为 error).

触发替换的常见路径: 切到异 provider 的模型、`/new`、`/reload`、fork、子会话.
并非显式 `/reload` 才会 stale —— provider 切换也可能内部走 session 替换.

**正确姿势**:

- 模块级缓存的 UI/通知函数, 调用处必须 `try/catch` 容错: stale 时降级
  (`console.error` 兜底) + 清缓存, 等下次 `session_start`/`model_select` 刷新.
- 不要让 UI 通知 (展示层) 的失败上抛到 chat/failover 主链.
- 或: 不缓存闭包, 改为每次从 fresh ctx 取 (仅当调用点本身在事件回调内时可行).

## 五条规则

| 规则 | 内容 | 对应 |
|---|---|---|
| R1 非阻塞 | 所有网络 `p().catch(log)`, 绝不 `await` | 不阻塞事件循环 |
| R2 模型门闩 | `!isMine` → 清状态栏 + `return`, 不发任何网络. 模型列表属 factory, 豁免 | 切换/启动非本 provider 时零网络 |
| R3 hasUI 门闩 | 账号级后台任务 (签到类) 额外加 `ctx.hasUI`, 防 pi-subagent 同进程 `createAgentSession` 重复触发 | 子会话不重复 |
| R4 锁只给副作用网络 | 写远端/写账号状态的操作用跨进程文件锁; 只读 GET (usage/billing) 不加锁 | 防多 pi 并发启动重复打副作用接口 |
| R5 幂等 | 被 R3/R4 放行的任务必须自身幂等 (按日记录/TTL), 失败仅日志不抛 | 重复触发是 no-op |

**为何只读 GET 不加锁**: 只读、幂等、按会话独立 footer; 模型门闩 (R2) 已挡掉非本 provider 的并发. 锁会让并发启动时 footer 串行延迟, 得不偿失. 锁只留给有副作用的签到类 (写远端 claim、写账号当日状态), 那才是并发会出错的.

## session_start 与 model_select 的一致性

切换模型到某 provider, 应与以该 provider 模型启动会话行为一致. 二者走同一 `activate` 即天然一致. 关键覆盖场景:

- 以非 codebuddy 模型启动 pi (session_start 因 R2 跳过 codebuddy 网络), 再切回 codebuddy → `model_select` 触发 `activate` 补上签到/额度. 这是 R2 门闩的必要补丁.

## 锁模块

跨进程文件锁用 `src/checkin-lock.ts`, 各 provider 同款:

- 位置: `~/.pi/agent/extensions/pi-<provider>-provider/checkin.lock`
- 原子: `openSync(path, "wx")` (O_CREAT|O_EXCL), 已存在抛 EEXIST
- 过期接管: 锁文件 mtime 超 TTL (默认 10min) 则强制接管, 防进程崩溃死锁
- 释放: 先读锁文件校验 PID 仍属本进程再 `unlinkSync`; 慢进程不得误删接管者的锁

锁定有副作用的后台任务:

```
const release = acquireCheckinLock(dir)
if (!release) { log("lock busy, skip"); return }
try { await sideEffectTask() } finally { release() }
```

## 审查清单

写/审 `session_start` 或 `model_select` 时逐条核对:

- [ ] 是否抽出 `activate`, 两事件共用
- [ ] 网络是否 `p().catch(log)` 非阻塞
- [ ] `!isMine` 是否清状态 + return, 零网络 (模型列表除外)
- [ ] 账号级后台任务是否加 `hasUI` 门闩
- [ ] 有副作用的任务是否走 `acquireCheckinLock`, 只读 GET 是否不加锁
- [ ] 后台任务是否幂等 (按日记录/TTL)
- [ ] 会话簿记是否只在 `session_start`, 未漏入 `activate`
- [ ] 模块级缓存的 `ctx`/`ctx.ui` 是否仅同步消费; 跨事件异步链调用的 UI/通知是否 `try/catch` 容错 stale 降级
