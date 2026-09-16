---
name: computer-use-best-practice
description: 当需要读取 macOS 上任意 App 的界面内容，或对它点击、输入、按键、滚动时阅读该技能
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

## `computer-use`优化原则(该原则永远不准删除)

- token 高效
- agent 使用无感(排除使用障碍)
- 调用方调用简单(深模块)
- 默认一律后台运行(不打扰用户)

## 目标寻址

所有针对窗口的命令共用同一套写法，任选其一：

| 写法 | 含义 |
|---|---|
| `1435:112` | 显式窗口，`windows` 的 TARGET 列可直接复制 |
| `Music` 或 `Zed#cpa-plugins` | 该应用 z 序最前的可操作窗口 |
| 省略 | 复用上一次的目标 |

```bash
computer-use open Music        # 后台拉起并记住目标
computer-use snapshot          # 目标省略，读刚拉起那个窗口
computer-use click t23         # 继续省略
computer-use use 音乐           # 只换目标，不执行动作
```

裸整数永远被当作动作参数而不是目标，所以 `click 500 235` 只有一个含义：在当前目标上点 PNG 像素 (500,235)。

应用名是本地化的：窗口列表里叫「音乐」，安装路径与 bundle id 里才叫 `Music`。两种写法都能用，脚本自己去安装清单换算。

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

`shown=` 是本次打印的元素数，`walked=` 是驱动这次走过了多少个元素，`unindexed=` 是有多少节点拿不到 token。后两个一起读才能判断「是不是还有东西没读到」，读法见坑点里的遍历成本。

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

判定动作真的生效，下列任一条成立即可：

- `observe` 里出现只有该动作才会造成的元素变化，例如按钮标签翻转；
- `verify` 返回 `verdict=satisfied`；
- 进度条或播放时间在间隔 1 秒的两次 `appshot` 之间持续增加；
- 应用原生接口确证，例如 `osascript -e 'tell application "Music" to get player state'` 返回 `Playing`。

实测可用的一招：找那个状态会写进标签的控件。音乐播放器的随机播放按钮，点击后 `observe` 报 `+ Button 随机播放 / - Button 不随机播放`，这种差分就是硬证据。反过来，如果差分内容与动作无关（比如刚启动的应用把界面加载完了），那不是你的动作造成的。

`verify` 的三态各有含义。`satisfied` 是成立，`unsatisfied` 是明确不成立，`unknown` 是驱动无法判定。`unknown` 等于没有证据，按没有证据上报。

`observe` 差分为空只说明 AX 树没有反映变化。

## 常用方式

**按应用名一路省略目标**

```bash
computer-use open Music
computer-use find 歌词            # 目标沿用上一步
computer-use click t23
```

**往输入框写文本**

`type` 带 `t<idx>` 时优先走 Cocoa 原生写入并回报 `value_readback`，无需激活前台。

```bash
computer-use appshot
computer-use type t7 "https://example.com"
computer-use key t7 return
```

**读小字或精确取点**

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

**等一个异步结果**

```bash
computer-use click t41 --wait t45 --timeout 3000
computer-use click t41 --wait media:playing
```

**在拖动类界面上框选**

四个坐标都取最近一次 `appshot` 的 PNG 像素。

```bash
computer-use drag 200 300 600 520
```

## 坑点

### 遍历成本

默认不下发遍历预算，交给驱动（深度 25、元素 2000）。脚本自己砍深度会让整棵子树消失，而耗时由树本身决定：实测音乐播放器的窗口，默认档 231 个元素、2.4 秒；砍到 `--depth 3` 只剩 111 个元素，还是 2.4 秒。收紧预算只在明确要少拿数据时用，不该当加速手段。

`find` 的投影只减少打印量，不减少驱动的遍历量，所以它省 token 不省时间。

应用窗口的 AX 树会带上全局菜单栏，那部分元素多且与窗口本身无关。默认的视口过滤会去掉菜单角色，`find` 与 `--all` 不会。

表头有两个完整性读数，用来判断「是不是还有东西没读到」：

- `unindexed=` 树里存在、但拿不到 token 的节点数。驱动只给可操作元素发索引，其余节点只出现在 `tree_markdown` 里：读得到，按不了 `t<idx>`。实测音乐播放器满树 425 个 markdown 节点 vs 231 个 elements，差 194。
- `tree=full | depth-limited(depth=N)`。`depth-limited` 表示最深元素正好停在请求深度上，下面可能还有更深的，加深一层再看。

两个都是保守下界：`unindexed` 只数驱动已经走到的部分，被深度砍掉的还没算进去。`find` 命中无索引节点时会打印 `~` 行标出来。

同一窗口在不同 `--depth` 之间切换，越界的菜单项会整批进出，`observe` 里看起来像新增或消失，实际什么都没发生。固定档位连续操作就不会看到这种噪声。

### 两套坐标

`appshot` 输出的 `ax=(x,y)` 是 AX 屏幕点，只用于判断元素的相对位置。像素操作必须读同一张 PNG 的坐标：`click`、`right-click`、`double-click`、`drag` 的目标，以及 `zoom` 的四个边界，都取 PNG 像素。

先 `zoom` 再点，得到的坐标是 zoom 图内的像素，要配 `--from-zoom` 才能直接用。

### 窗口落在屏幕外

平铺窗口管理器（OmniWM、AeroSpace）把非焦点窗口推到屏幕外。实测在 1920x1080 单显示器上，Zed 的三个窗口、Helium 与刚拉起的音乐播放器都在 `x=1919`，只有最左一列像素可见。

这事按几何判定，驱动报的 `is_on_screen` 不能用：这些窗口全都报 `true`。脚本按窗口矩形与屏幕矩形实算，`clipped` 表示被裁掉一部分，`off-viewport` 表示整个在屏幕外。

离屏不影响读取，也不影响 `t<idx>` 元素动作。实测对 `x=1919` 的窗口做元素点击，`observe` 正常回出差分。能不能投递以输出里的 `routes=` 行为准，那是驱动的判定，不要替它推断。

要用像素坐标时先 `computer-use move` 把窗口挪回屏幕内。抢焦点、切工作区或移动窗口这类动作，先说明影响并取得许可。

### 路由诊断

`routes=` 行来自驱动，逐条列出 `accessibility`、`window_pointer`、`pid_keyboard` 三种投递方式此刻是否可用，以及被拒的原因。它是判断动作为什么落不下去的权威来源，只在有路由不可用或者树为空时才打印。

树为空时它给出原因，例如 `ax=ax_unresolved accessibility=refused(off_space_or_ax_unresolved)`。这种情况改用 `appshot` 走像素，或者确认窗口是不是还在初始化。

### find 不污染观察基线

`find` 与 `snapshot --query` 的投影只发生在打印层，快照缓存里仍是完整树。所以 `find` 之后紧接的动作，`observe` 的基线依然完整，投影丢掉的那些元素不会被误报成新增。

这条踩过：把驱动侧的投影结果当作快照存下来之后，一次点击的差分虚报出 73 个新增元素。

### 菜单调用会真实展开菜单

`menu` 的逐层解析会真的把菜单打开。目标应用正被人使用时不要用它探测菜单路径，菜单栏进入追踪状态会吞掉使用者接下来的点击与按键。

想先知道菜单里有什么，用只读的 `find` 就够：菜单项本来就在 AX 树里，`find <应用> <词>` 直接读出标签，例如实测 `find 退出登录` 回 6 行，其中 5 行是可点按的 `MenuItem`。

### 应用名可能多付一次清单往返

按名字找窗口时，如果名字匹配不上（本地化应用名就是这种情况），脚本去读一次安装清单换算，并按天缓存这份清单。命中路径不付这次往返。

按应用名寻址比 `<pid>:<wid>` 多一次 `list_windows` 调用，单次约 2 秒。同一个应用的连续操作写成省略目标的串行命令更省。

### 前台升级

驱动有两档投递，默认档是后台：`click`、`type`、`key`、`scroll` 都带 `delivery_mode=background`，不抢焦点、不切工作区、不动光标。

决定是否碰屏幕的是寻址方式而不是命令本身。元素目标 `t<idx>` 走 AX 档，后台窗口、隐藏窗口、别的 Space 上的窗口都能用；像素坐标走 CGEvent 档，要求那个点落在屏幕可见范围内。

只有后台路径确认失败，且任务必须依赖前台输入时，才用 `front` 或 `--foreground`，并说明影响。

实测音乐播放器的元素点击全程 `route=accessibility delivery=background`，使用者那一侧没有任何前台变化。

### 文本控件

原生 `AXTextField` 不支持 `AXPress`，调用会报 `-25206`。`computer-use` 对文本控件自动改为中心像素点击，或直接走 `type` 原生写入。

### 双击

驱动的后台双击缺少 no-raise 激活前奏，非前台 AppKit 窗口会被静默忽略，例如 Audirvana 列表。`double-click` 默认短暂置前目标窗口，随后恢复原前台。

### verify 的边界

`value`、`selected`、`enabled` 只对具备该属性的角色成立。`AXWindow` 这类角色没有对应属性，驱动返回 `unknown/unsupported_predicate`。

选择器命中多个元素时脚本直接拒绝，先用更精确的 `label` 收窄。`exists` 没有否定形式，断言「不存在」驱动不接受。

### 调用契约

目标必须写成 `<pid>:<wid>` 或应用名，或者从上一次沿用。脚本不会隐式猜测前台窗口；无目标可用时直接报错并给出下一步命令。

`windows` 与 `open` 输出的 TARGET 列可以直接复制到任意子命令。

所有子命令都会在内容之后空一行输出 `duration_ms=<毫秒>`，包括等待超时、参数报错与异常退出。`--json` 模式除外。

### 驱动身份决定 TCC 授权

用 `cua-driver serve` 在终端里直接启动时，TCC 归属终端进程，Accessibility 与 Screen Recording 都会缺失，每次调用弹出授权闸门。此时 `get_window_state` 仍返回结构，但截图落盘失败，脚本报 `未能取得有效图片`。

以 App 身份启动即可带上已有授权：

```bash
open -n -g -a CuaDriver --args serve        # 以 App 身份启动守护进程
cua-driver permissions grant                # 授权并验证
cua-driver permissions status               # 只读复核，不弹窗
```

`computer-use` 自身不启动驱动、不申请权限，只如实报告失败。
