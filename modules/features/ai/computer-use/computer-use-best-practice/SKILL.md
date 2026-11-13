---
name: computer-use-best-practice
description: 通过 `cua-driver` 操作 macOS 任意 App 的界面：读取 AX 树与截图，点击、输入、按键、滚动、调用菜单
---

# computer-use

控制 macOS 应用界面直接用驱动自带的 CLI `cua-driver`，没有包装脚本。驱动的参数与行为随版本变化，以它自己的文档为准：

```bash
cua-driver list-tools                  # 全部工具
cua-driver describe run_steps          # 动作 + 动作后差分 + 等待/断言，默认用它行动
cua-driver describe get_window_state   # 读窗口：query 过滤、since 差分、tree_format
cua-driver call <工具> '<JSON 参数>'    # 调用工具
```

## 原则

- token 高效：先 `query` 过滤、限 `max_elements`，重读用 `since` 差分，不整树全量读取
- 使用无感：遇到障碍（权限、应用名本地化、窗口不可见）先排除，不把排查甩给用户
- 调用简单：已知的动作合成一次 `run_steps`，不拆成读、动、再读
- 默认后台运行：不打扰用户，不抢焦点

## 做法

- 行动：`run_steps`，一次调用完成若干动作，加 `observe:{}` 得到只含变化行的差分。步骤里可以直接写 `app`、`role`、`name` 定位元素，不必先读 token
- 读界面：`get_window_state` 默认返回压缩的 Markdown 树、最多 250 个节点；大树用 `query` 过滤，动作之后重读用 `since:"latest"`
- 默认后台投递：元素 token 走 AX，不抢焦点；像素坐标要求窗口在屏幕内可见
- 只有后台投递被拒、任务又必须依赖前台输入时，才用 `foreground_fallback` 或 `delivery_mode:"foreground"`，并先说明会激活窗口、可能移动指针

## 本机注意

- **应用名是本地化的。** `list_windows` 的 `app` 过滤按显示名子串或 bundle id 精确匹配：`屏幕共享` 与 `com.apple.ScreenSharing` 都命中，英文名 `Screen Sharing` 命中 0 个窗口。先 `cua-driver call list_apps` 查 bundle id，再用它
- **权限归属 CuaDriver.app。** 授权与复核走 `cua-driver permissions grant` 与 `cua-driver permissions status`；在终端里直接 `cua-driver serve` 会让授权归属终端，Accessibility 与 Screen Recording 缺失
- **安装与升级走 Homebrew cask `cuadriver`**，声明在 `modules/features/ai/computer-use/default.nix`，升级用 `brew upgrade --cask cuadriver`。不要用 `cua-driver skills install`：它会往 nix 管理的 `~/.agents/skills/` 写链接
- **沙箱里不可用**，`cua-driver` 在沙箱内是报错桩
