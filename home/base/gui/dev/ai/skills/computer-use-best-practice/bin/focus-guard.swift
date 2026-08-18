// focus-guard: macOS 焦点保镖
// 记录启动时的 frontmost app，监听 NSWorkspace 焦点激活通知，
// 仅拦截指定目标 app（--target）的抢焦点行为，放行用户主动切换和其他 app。
// didActivateApplicationNotification 不区分激活来源（用户点击 vs app 调 activate），
// 所以必须指定 target，避免误拦截用户主动切换。
// 原理依赖 didActivateApplicationNotification（macOS 10.6+，文档稳定），
// activate(options:) 文档保证线程安全，无需 main run loop。

import Cocoa

let args = CommandLine.arguments

if args.count < 2 || args.contains("--help") || args.contains("-h") {
    FileHandle.standardError.write("""
    focus-guard <seconds> [--target <name>...] [--verbose]

    在指定秒数内保护当前前台 app 不被「指定目标 app」抢焦点。
    先后台启动 guard，再启动目标 app；guard 退出前目标的抢焦点都会被切回原前台。

    参数：
      seconds             保护时长（秒，正数）
      --target <name>     会抢焦点的目标 app 名（可多次指定）；不指定则拦截所有非 prior 的激活
      --verbose, -v       打印每次激活事件（调试用）
      -h, --help          显示本帮助

    示例：
      focus-guard 15 --target QwenWorkCN --target "QoderWork CN" &
      open -a QwenWorkCN   # 只有 QwenWorkCN 抢焦点会被拦，用户切换不受影响

    首次使用由启动器自动编译（约 30s，仅一次），产物缓存在 ~/.cache/computer-use/
    无侵入：不注入、不 hook、不改目标应用，仅在系统焦点通知上做反向切换。

    """.data(using: .utf8)!)
    exit(args.count < 2 ? 2 : 0)
}

guard let secs = Double(args[1]), secs > 0 else {
    FileHandle.standardError.write("focus-guard: 无效时长 '\(args[1])'，需要正数秒\n".data(using: .utf8)!)
    exit(2)
}

// 解析 --target 和 --verbose
var targets: [String] = []
var verbose = false
var i = 2
while i < args.count {
    if args[i] == "--target" && i + 1 < args.count {
        targets.append(args[i + 1]); i += 2
    } else if args[i] == "--verbose" || args[i] == "-v" {
        verbose = true; i += 1
    } else {
        i += 1
    }
}

let ws = NSWorkspace.shared
guard let prior = ws.frontmostApplication else {
    FileHandle.standardError.write("focus-guard: 无法获取当前前台 app\n".data(using: .utf8)!)
    exit(1)
}

let priorPid = prior.processIdentifier
let priorName = prior.localizedName ?? "unknown"
let targetDesc = targets.isEmpty ? "任何非 prior" : targets.joined(separator: ", ")

FileHandle.standardError.write("focus-guard: 保护 '\(priorName)' (pid \(priorPid)) \(secs)s，拦截目标: \(targetDesc)\n".data(using: .utf8)!)

let center = ws.notificationCenter

// 判断激活的 app 是否是需要拦截的目标
func shouldSuppress(_ app: NSRunningApplication) -> Bool {
    guard app.processIdentifier != priorPid else { return false }
    if targets.isEmpty { return true } // 未指定 target：拦所有非 prior（旧行为）
    let name = app.localizedName ?? ""
    let bundle = app.bundleIdentifier ?? ""
    // 也比对可执行文件名（如 "QwenWorkCN" 可能本地化为 "千问办公"，但 exec 名不变）
    let execURL = app.executableURL?.lastPathComponent ?? ""
    return targets.contains { t in
        name.contains(t) || bundle.contains(t) || execURL.contains(t)
    }
}

// 订阅焦点激活通知
let observer = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil) { n in
    guard let info = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
    let name = info.localizedName ?? "?"
    if verbose {
        let exec = info.executableURL?.lastPathComponent ?? "?"
        FileHandle.standardError.write("focus-guard: 事件 \(name) (pid \(info.processIdentifier)) exec=\(exec)\n".data(using: .utf8)!)
    }
    if shouldSuppress(info) {
        prior.activate(options: [.activateAllWindows])
        FileHandle.standardError.write("focus-guard: 拦截 \(name) 抢焦点，切回 \(priorName)\n".data(using: .utf8)!)
    }
}

// 到期清理退出
DispatchQueue.global().asyncAfter(deadline: .now() + secs) {
    center.removeObserver(observer)
    FileHandle.standardError.write("focus-guard: 到期退出\n".data(using: .utf8)!)
    exit(0)
}

// 兜底：asyncAfter 未能触发时由 runloop 超时退出
RunLoop.main.run(until: Date(timeIntervalSinceNow: secs + 2))
