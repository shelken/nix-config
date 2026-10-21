---
name: computer-use-best-practice
description: 通过全局 CLI `computer-use` 操作 macOS 任意 App 的界面：读取 AX 树与截图，点击、输入、按键、滚动、调用菜单
---

# computer-use

控制 macOS 应用界面走全局 CLI `computer-use`。它把原始 AX 树裁剪成视口内元素与有界差分，直接读原始树会撑爆上下文。

命令的参数、标志与输出字段写在脚本自带帮助里：

```bash
computer-use --help                # 总览与后台契约
computer-use --help target         # 目标寻址的三种写法
computer-use --help <子命令>        # 单个命令的全部细节
computer-use --help output         # 动作结果字段语义
```

所有子命令都会在内容之后空一行输出 `duration_ms=<毫秒>`，包括等待超时、参数报错与异常退出；`--json` 模式除外。

## `computer-use`优化原则(该原则永远不准删除)

- token 高效
- agent 使用无感(排除使用障碍)
- 调用方调用简单(深模块)
- 默认一律后台运行(不打扰用户)

## 目标寻址

所有针对窗口的命令共用同一套写法，任选其一：

| 写法 | 含义 |
|---|---|
| `1435:112` | 显式窗口（`<pid>:<wid>`），`windows` 与 `open` 输出的 TARGET 列可直接复制 |
| `Music` 或 `Zed#cpa-plugins` | 该应用 z 序最前的可操作窗口 |
| 省略 | 复用上一次的目标 |

```bash
computer-use open Music        # 后台拉起并记住目标
computer-use snapshot          # 目标省略，读刚拉起那个窗口
computer-use click t23         # 继续省略
computer-use use 音乐           # 只换目标，不执行动作
```

脚本不会隐式猜测前台窗口；无目标可用时直接报错并给出下一步命令。

裸整数永远被当作动作参数而不是目标，所以 `click 500 235` 只有一个含义：在当前目标上点 PNG 像素 (500,235)。

应用名是本地化的：窗口列表里叫「音乐」，安装路径与 bundle id 里才叫 `Music`。两种写法都能用，脚本自己去安装清单换算。

按名字找窗口时，如果名字匹配不上（本地化应用名就是这种情况），脚本去读一次安装清单换算，并按天缓存这份清单。命中路径不付这次往返。按应用名寻址比 `<pid>:<wid>` 多一次 `list_windows` 调用，单次约 2 秒。同一个应用的连续操作写成省略目标的串行命令更省。

## SOP

四步。每步末尾给出完成判据，判据不成立就不要进入下一步。

### 1. 定位窗口

```bash
computer-use apps              # 已装应用与运行状态
computer-use open Music        # 未启动则后台拉起，并记住目标
computer-use windows           # TARGET / Z / APP / TITLE / BOUNDS / STATE
```

判据：手上有一个 `TARGET` 或应用名。`STATE` 列直接标出 `clipped` 与 `off-viewport`。

`open` 不抢前台，被拉起应用的窗口可能落在屏幕外，这不影响后续 AX 读写。

### 2. 读取界面

```bash
computer-use appshot [目标]           # AX 树与 PNG 截图一起拿
computer-use snapshot [目标]          # 只要 AX 树，省掉截图开销
computer-use find [目标] <匹配词>      # 只回命中项及其祖先链
```

判据：输出里有 `t<idx>` 元素 token，需要像素操作时还要有 PNG 尺寸。

大树先用 `find` 定位再操作。实测音乐播放器的 231 个元素里，`find 随机播放` 只回 7 行。

### 3. 执行动作

```bash
computer-use click t41
computer-use type t7 "搜索词"
computer-use key t3 return
computer-use scroll t12 down
computer-use menu 账户 登录…
```

每个动作结束后脚本自动重采一次，打印 `observe` 差分，旧 `t<idx>` 立即失效。

判据：`observe` 的 `added`、`removed`、`changed` 与预期一致。

### 4. 确认结果

```bash
computer-use verify Button 播放 selected true
computer-use click t41 --wait t45
```

判据：`verify` 退出码为 0，或 `--wait` 输出 `verdict=confirmed`。

## 确认纪律

`effect: unverifiable` 只说明动作投递出去了。选中态不等于执行态：在 Audirvana、Apple Music、访达这类列表里，点击只让该行获得焦点，播放要另发 `double-click`，或在选中后发 `key space`。

`enabled=true` 与 `effect=unverifiable` 都不证明控件可操作，也都不证明它不可操作。驱动对 generic click 没有独立回执（只有列表项的 `AXSelected` 能确认），所以 `effect=unverifiable` 是常态：实测同一个传输按钮点下去报 `unverifiable`，树里却真的从「播放」变成「暂停」。动作到底有没有发生，只能看 `observe` 差分、`verify`、或截图目视。

`observe` 差分为空只说明 AX 树没有反映变化。此时脚本会打一行 `hint=`，说明这次投递没有任何回执，并给出 `--foreground` 与像素路径两条升级路线。

判定动作真的生效，下列任一条成立即可：

- `observe` 里出现只有该动作才会造成的元素变化，例如按钮标签翻转；
- `verify` 返回 `verdict=satisfied`；
- 进度条或播放时间在间隔 1 秒的两次 `appshot` 之间持续增加；
- 应用原生接口确证，例如 `osascript -e 'tell application "Music" to get player state'` 返回 `playing`。

实测可用的一招：找那个状态会写进标签的控件。音乐播放器的随机播放按钮，点击后 `observe` 报 `+ Button 随机播放 / - Button 不随机播放`，这种差分就是硬证据。反过来，如果差分内容与动作无关（比如刚启动的应用把界面加载完了），那不是你的动作造成的。

`verify` 的三态各有含义。`satisfied` 是成立，`unsatisfied` 是明确不成立，`unknown` 是驱动无法判定。`unknown` 等于没有证据，按没有证据上报。

`verify` 的 `value`、`selected`、`enabled` 只对具备该属性的角色成立。`AXWindow` 这类角色没有对应属性，驱动返回 `unknown/unsupported_predicate`。选择器命中多个元素时脚本直接拒绝，先用更精确的 `label` 收窄。`exists` 没有否定形式，断言「不存在」驱动不接受。

## 常用方式

**往输入框写文本**

`type` 带 `t<idx>` 时优先走 Cocoa 原生写入并回报 `value_readback`，无需激活前台。

```bash
computer-use appshot
computer-use type t7 "https://example.com"
computer-use key t7 return
```

**读小字或精确取点**

`appshot` 输出的 `ax=(x,y)` 是 AX 屏幕点，只用于判断元素的相对位置。像素操作必须读同一张 PNG 的坐标：`click`、`right-click`、`double-click`、`drag` 的目标，以及 `zoom` 的四个边界，都取 PNG 像素。

```bash
computer-use zoom 1435:112 300 200 420 260      # 产出放大 JPEG
computer-use click 60 30 --from-zoom            # 坐标是 zoom 图内像素
```

**展开元素的上下文菜单**

```bash
computer-use right-click t18
```

**按菜单路径直接调用**

```bash
computer-use menu 账户 登录…
```

`menu` 的逐层解析会真的把菜单打开。目标应用正被人使用时不要用它探测菜单路径，菜单栏进入追踪状态会吞掉使用者接下来的点击与按键。

想先知道菜单里有什么，用只读的 `find` 就够：菜单项本来就在 AX 树里，`find <应用> <词>` 直接读出标签，例如实测 `find 退出登录` 回 6 行，其中 5 行是可点按的 `MenuItem`。

**等一个异步结果**

```bash
computer-use click t41 --wait t45 --timeout 3000
computer-use click t41 --wait media:playing
```

`--wait media:*` 等的是**系统级** now-playing，不是目标窗口那个应用：实测对着文本编辑窗口等 `media:playing`，报回来的是浏览器里正在播的视频。输出行带 `app=<bundle id>`，先核对它是不是你操作的那个应用。`media-control` 缺失或执行失败时命令直接报错退出，不会退化成 `timeout`——那种情况下这次等待根本无法判定。

**在拖动类界面上框选**

四个坐标都取最近一次 `appshot` 的 PNG 像素。

```bash
computer-use drag 200 300 600 520
```

## 后台投递与前台升级

驱动有两档投递，默认档是后台：`click`、`type`、`key`、`scroll` 都带 `delivery_mode=background`，不抢焦点、不切工作区、不动光标。

决定是否碰屏幕的是寻址方式而不是命令本身。元素目标 `t<idx>` 走 AX 档，后台窗口、隐藏窗口、别的 Space 上的窗口都能用；像素坐标走 CGEvent 档，要求那个点落在屏幕可见范围内。

只有后台路径确认失败，且任务必须依赖前台输入时，才用 `front` 或 `--foreground`，并说明影响。

实测音乐播放器的元素点击全程 `route=accessibility delivery=background`，使用者那一侧没有任何前台变化。

驱动的后台双击缺少 no-raise 激活前奏，非前台 AppKit 窗口会被静默忽略，例如 Audirvana 列表。`double-click` 默认短暂置前目标窗口，随后恢复原前台。

## 按需阅读

下列情形才读对应文件，其余时候不必读：

- `zoom` 截到的区域与请求不符、点击落点错位，或需要把 zoom 图内位置回推成窗口坐标：`references/coordinates.md`
- 要解读输出表头的 `shown=`、`walked=`、`unindexed=`、`tree=`，怀疑还有元素没读到，打算用 `--depth` 调遍历预算，或 `observe` 里出现大批无关的新增或消失：`references/traversal.md`
- `windows` 的 `STATE` 为 `clipped` 或 `off-viewport` 且要用像素坐标，动作落不下去，输出出现 `routes:` 行或树为空，点击文本框报 `-25206` 或输出带 `note=`：`references/delivery.md`
- 脚本报 `未能取得有效图片`，或每次调用都弹出授权闸门：`references/permissions.md`
