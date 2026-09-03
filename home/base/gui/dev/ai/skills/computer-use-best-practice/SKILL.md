---
name: computer-use-best-practice
description: 当 需要阅读mac上任意App界面的内容/控制任意App/点击任意App 时阅读该技能
---

## 核心原则与 CLI 工具要求（禁止删除）

**最高原则：Token 极致高效率、语义明确与所见即所得。**
本技能必须优先使用全局 CLI `computer-use`（底层由 Nix 原生封装，源码位于同级 `scripts/computer-use.ts`），杜绝直接暴露庞大臃肿且充满缓存垃圾的原始 AX 树。

`computer-use` 脚本必须严格满足以下硬性保证：
1. **默认不打扰用户**：优先使用后台 AX 读取与操作，不抢焦点、不切工作区、不移动窗口。只有后台路径失败且任务必须依赖前台输入时，才可在说明影响后使用 `front` 或 `--foreground`；
2. **Token 极致高效率**：默认浅层扫描并仅输出窗口视口内元素。`snapshot` 缓存本次 token，后续动作直接复用，不重复扫描 AX 树；
3. **有界遍历**：默认 `depth=3`、`max-elements=300`。`query` 只过滤返回内容，不能降低 AX 遍历成本；
4. **坐标分域**：输出的 `ax=(x,y)` 只用于辅助定位。像素操作必须先使用 `--screenshot <path>`，再从 PNG 读取坐标；
5. **语义与动作完备**：从 AXDescription/Help 提取语义说明；支持单击、双击、文本写入、按键和滚动；
6. **显式前台升级**：`front` 与 `--foreground` 只处理明确要求的前台交互，不自动移动窗口；
7. **状态透明**：动作输出 `effect`、`route`、`delivery`、`evidence`、`state` 和 `duration_ms`。只有 `state=confirmed` 表示驱动已验证结果；
8. **有界后置差分验证**：支持 `--wait <t<idx>>` 自动在动作前后对比目标属性（数值位移、选中态翻转等）；或显式传入 `--wait media:playing` 按需验证系统媒体状态（普通操作默认不碰媒体通道）；
9. **全命令耗时输出**：所有子命令（无论执行成功、等待超时、参数报错还是异常退出）必须在末尾与上方输出内容通过空行区隔，统一输出 `duration_ms=<毫秒>` 耗时行（`--json` 原始模式除外），禁止任何退出路径遗漏。

## 端到端完整闭环操作命令

```bash
# 0. 查看最近常用应用（🟢 开启中(带PID) / ⚪️ 未开启，按真实使用时间倒序）
computer-use apps [--recent [N]]
# 支持按名称或 Bundle ID 搜索已安装应用
computer-use apps zed

# 1. 启动/定位应用（已有窗口直接返回 PID/WID，未启动则冷启动并等待就绪）
computer-use open <name|bundle_id>

# 2. 发现已有窗口 (获取 pid 与 window_id)
computer-use windows

# 3. 读界面，默认 depth=3、max-elements=300，并缓存本次 token
computer-use snapshot <pid> <wid>
# 选项:
#   --depth <N>         调整遍历深度
#   --max-elements <N>  调整元素预算
#   --query <str>       过滤返回内容和 Token，不减少底层遍历
#   --screenshot <path> 保存 PNG；后续像素操作只能使用该 PNG 的坐标，建议写入 $TMPDIR
#   --all               输出包含滚出视口的缓存元素
#   --json              输出原始 JSON 数据

# 4. 常见操作，t<idx> 使用最近一次 snapshot 的缓存 token
computer-use click <pid> <wid> t<idx> [action] [--foreground]
computer-use double-click <pid> <wid> t<idx> [--foreground]

# 动作后置验证（规避脆弱的手动 sleep）：
# - 通用 AX 属性差分验证：等待目标 t<idx> 属性位移或改变
computer-use click <pid> <wid> t41 --wait t45 [--timeout 2000]
# - 系统媒体状态验证（仅在目标应用支持且调用者显式要求时代入）：
computer-use click <pid> <wid> t41 --wait media:playing

# 只有 AX 不可用的自绘控件才使用像素路径。x/y 是最近 PNG 的像素坐标
computer-use snapshot <pid> <wid> --screenshot "$TMPDIR/computer-use-window.png"
computer-use click <pid> <wid> <x> <y> [--foreground]
computer-use double-click <pid> <wid> <x> <y> [--foreground]

# 输入文本：优先走 Cocoa 原生 set_value 毫秒级后台写入并带 value_readback 验证；支持输入至指定元素或当前焦点
computer-use type <pid> <wid> t<idx> "YOASOBI" [--foreground]
computer-use type <pid> <wid> "搜索关键词" [--foreground]

# 按键与快捷键（支持指向特定控件后台聚焦输入，无需激活前台）
computer-use key <pid> <wid> t<idx> return
computer-use key <pid> <wid> return [cmd|shift|option|ctrl..]
computer-use key <pid> <wid> space

# 滚动
computer-use scroll <pid> <wid> t<idx> down [line|page] [--foreground]

# 5. 显式前台升级，仅在后台路径失败且任务必须依赖前台输入时使用
computer-use front <pid> <wid>

# 6. 窗口移动与调整大小
computer-use move <pid> <wid> <x> <y> [w] [h]
```

---

## 严守验证客观纪律（禁止虚假确认）

**严禁将“尝试操作了”当作“操作成功了”，绝不能用 `effect: unverifiable` 或仅仅是列表项高亮来推定结果！**

1. **选中态不代表执行态**：
   - 绝大多数桌面应用（Audirvana、Apple Music、访达、IDE 列表）中，点击某行只会使其获得焦点或选中态（`selected: true` / `sel`），**绝不代表触发了播放或打开动作**。
2. **播放/运行的铁证标准**（满足其一即可断定，但必须有客观证据）：
   - **进度条持续位移**：相隔 1 秒调用两次 `snapshot`，观察进度条（`Slider`）或播放时间（`Time`）的数值发生持续增加；
   - **按钮状态明确翻转**：播放按钮语义发生变化（如 `Play` 翻转为 `Pause`，或相关状态字段翻转）；
   - **原生底层状态确证**：通过应用原生接口直接读取（例如 Audirvana 运行 `osascript -e 'tell application "Audirvana" to get player state'` 返回 `Playing`）。

---

## 规则与实测坑位

- **庞大列表与 AX 遍历截断**：
  - Audirvana、音乐库、上万文件的访达窗口会让深层 DFS 遍历等待 20 秒
  - 先用默认浅层快照读取全局控件。需要深层自绘列表时，使用 `--screenshot`；`query` 不能消除遍历成本
- **列表项播放方式**：
  - 单击只能用于选中；若要播放列表曲目，必须使用 `double-click <pid> <wid> t<idx>` 或在选定后发送 `key <pid> <wid> space`。
- **平铺窗口管理器（OmniWM / AeroSpace）离屏陷阱**：
  - 后台 AX 操作不需要移动窗口
  - 像素操作要求窗口可见。需要抢焦点、切工作区或移动窗口时，先说明影响并取得用户明确许可
- **输入框操作**：
  - 原生 `AXTextField` 不支持 `AXPress`（调用会报 `-25206`）；`computer-use` 对其已自动优化为 `confirm` 或使用 `type` 直接写入。
