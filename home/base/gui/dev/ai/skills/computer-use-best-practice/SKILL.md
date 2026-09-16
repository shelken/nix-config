---
name: computer-use-best-practice
description: 当需要读取 macOS 上任意 App 的界面内容，或对它点击、输入、按键、滚动时阅读该技能
---

# computer-use

控制 macOS 应用界面走全局 CLI `computer-use`。它把原始 AX 树裁剪成视口内元素与有界差分，直接读原始树会撑爆上下文。

命令的参数、标志与输出字段写在脚本自带帮助里：

```bash
computer-use --help                # 总览与硬性契约
computer-use --help <子命令>        # 单个命令的全部细节
computer-use --help output         # 动作结果字段语义
```

## SOP

四步。每步末尾给出完成判据，判据不成立就不要进入下一步。

### 1. 定位窗口

```bash
computer-use apps                  # 已装应用与运行状态，「开启中」表示进程在跑
computer-use open Audirvana        # 未启动则拉起并等待窗口就绪
computer-use windows               # 拿到 pid 与 window_id
```

判据：手上有一对可用的 `<pid> <wid>`。

窗口列表里的应用名会被系统本地化，`TextEdit` 显示为「文本编辑」，`Finder` 显示为「访达」。

### 2. 读取界面

```bash
computer-use appshot <pid> <wid>       # AX 树与 PNG 截图一起拿
computer-use snapshot <pid> <wid>      # 只要 AX 树，省掉截图开销
```

判据：输出里有 `t<idx>` 元素 token，需要像素操作时还要有 PNG 尺寸。

两者都会刷新动作缓存，`t<idx>` 从这里取。

### 3. 执行动作

```bash
computer-use click <pid> <wid> t41
computer-use type <pid> <wid> t7 "搜索词"
computer-use key <pid> <wid> t3 return
computer-use scroll <pid> <wid> t12 down
```

每个动作结束后脚本自动重采一次，打印 `observe` 差分，旧 `t<idx>` 立即失效。

判据：`observe` 的 `added`、`removed`、`changed` 与预期一致。

### 4. 确认结果

```bash
computer-use verify <pid> <wid> Button 播放 selected true
computer-use click <pid> <wid> t41 --wait t45
```

判据：`verify` 退出码为 0，或 `--wait` 输出 `verdict=confirmed`。

## 确认纪律

`effect: unverifiable` 只说明动作投递出去了。选中态不等于执行态：在 Audirvana、Apple Music、访达这类列表里，点击只让该行获得焦点，播放要另发 `double-click`，或在选中后发 `key <pid> <wid> space`。

判定播放或运行需要客观证据，下列任一条成立即可：

- 进度条或播放时间在间隔 1 秒的两次 `appshot` 之间持续增加；
- 播放按钮语义翻转，例如 `Play` 变 `Pause`；
- `verify` 返回 `verdict=satisfied`；
- 应用原生接口确证，例如 `osascript -e 'tell application "Audirvana" to get player state'` 返回 `Playing`。

`verify` 的三态各有含义。`satisfied` 是成立，`unsatisfied` 是明确不成立，`unknown` 是驱动无法判定。`unknown` 等于没有证据，按没有证据上报。

`observe` 差分是同一份新状态的读数，可以直接引用。差分为空只说明 AX 树没有反映变化。

## 常用方式

**往输入框写文本**

`type` 带 `t<idx>` 时优先走 Cocoa 原生写入并回报 `value_readback`，无需激活前台。

```bash
computer-use type 1435 112 t7 "https://example.com"
computer-use key 1435 112 t7 return
```

**读小字或精确取点**

```bash
computer-use zoom 1435 112 300 200 420 260      # 产出放大 JPEG
computer-use click 1435 112 60 30 --from-zoom   # 坐标是 zoom 图内像素
```

**展开元素的上下文菜单**

```bash
computer-use right-click 1435 112 t18
```

**等一个异步结果**

```bash
computer-use click 1435 112 t41 --wait t45 --timeout 3000
computer-use click 1435 112 t41 --wait media:playing
```

**在拖动类界面上框选**

四个坐标都取最近一次 `appshot` 的 PNG 像素。

```bash
computer-use drag 1435 112 200 300 600 520
```

## 坑点

### 遍历成本与截断噪声

Audirvana、音乐库、上万文件的访达窗口会让深层遍历等待 20 秒。先用默认浅层快照读全局控件，需要深层自绘列表时改用截图。`--query` 只过滤返回内容，不降低遍历成本。

截断会让 `observe` 产生噪声：越过 `max-elements` 边界的一批元素成批出现在 `added` 或 `removed` 里。实测某终端窗口 `removed=20` 全是越界菜单项。

### 两套坐标

`appshot` 输出的 `ax=(x,y)` 是 AX 屏幕点，只用于判断元素的相对位置。像素操作必须读同一张 PNG 的坐标：`click`、`right-click`、`double-click`、`drag` 的目标，以及 `zoom` 的四个边界，都取 PNG 像素。

先 `zoom` 再点，得到的坐标是 zoom 图内的像素，要配 `--from-zoom` 才能直接用。

### 离屏窗口

平铺窗口管理器（OmniWM、AeroSpace）会把窗口推到屏幕外，例如 `bounds.x=1919`。

读取与截图对离屏窗口依然有效。输入投递要求窗口真实可见，驱动会以 `point lies outside window frame; background delivery refused` 拒绝，`click` 与 `scroll` 都失败。

`appshot` 的 `bounds=` 就是判据：`x` 超出屏幕宽度即说明窗口被推到屏外。这种情况要抢焦点、切工作区或移动窗口时，先说明影响并取得许可。

### 前台升级

默认走后台投递，不抢焦点、不切工作区、不移动窗口。后台路径失败且任务必须依赖前台输入时，才用 `front` 或 `--foreground`，并说明影响。

### 文本控件

原生 `AXTextField` 不支持 `AXPress`，调用会报 `-25206`。`computer-use` 对文本控件自动改为中心像素点击，或直接走 `type` 原生写入。

### 双击

驱动的后台双击缺少 no-raise 激活前奏，非前台 AppKit 窗口会被静默忽略，例如 Audirvana 列表。`double-click` 默认短暂置前目标窗口，随后恢复原前台。

### verify 的边界

`value`、`selected`、`enabled` 只对具备该属性的角色成立。`AXWindow` 这类角色没有对应属性，驱动返回 `unknown/unsupported_predicate`。

选择器命中多个元素时脚本直接拒绝，先用更精确的 `label` 收窄。`exists` 没有否定形式，断言「不存在」驱动不接受。

### 调用契约

针对窗口的命令必须显式给出 `<pid> <wid>`，脚本不会隐式猜测前台窗口。缺少参数时脚本输出错误原因与查询参数的标准路径。

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
