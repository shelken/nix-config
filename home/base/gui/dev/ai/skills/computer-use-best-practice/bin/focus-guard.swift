// focus-guard: macOS 焦点保镖
// 记录启动时的 frontmost app，监听 NSWorkspace 焦点激活通知，
// 任何其他 app 抢焦点时立即把焦点切回原 app，到期退出。
// 原理依赖 didActivateApplicationNotification（macOS 10.6+，文档稳定），
// activate(options:) 文档保证线程安全，无需 main run loop。

import Cocoa

let args = CommandLine.arguments

if args.count < 2 || args.contains("--help") || args.contains("-h") {
    FileHandle.standardError.write("""
    focus-guard <seconds>

    在指定秒数内保护当前前台 app 不被其他 app 抢焦点。
    先后台启动 guard，再启动目标 app；guard 退出前所有抢焦点的行为都会被切回原前台。

    参数：
      seconds    保护时长（秒，正数）
      -h, --help 显示本帮助

    示例：
      focus-guard 15 &       # 后台保护 15 秒
      open -a SomeApp        # 在保护窗口内启动抢焦点的 app
      kill %1                # 提前结束

    首次使用由启动器自动编译（约 30s，仅一次），产物缓存在 ~/.cache/computer-use/
    无侵入：不注入、不 hook、不改目标应用，仅在系统焦点通知上做反向切换。

    """.data(using: .utf8)!)
    exit(args.count < 2 ? 2 : 0)
}

guard let secs = Double(args[1]), secs > 0 else {
    FileHandle.standardError.write("focus-guard: 无效时长 '\(args[1])'，需要正数秒\n".data(using: .utf8)!)
    exit(2)
}

let ws = NSWorkspace.shared
guard let prior = ws.frontmostApplication else {
    FileHandle.standardError.write("focus-guard: 无法获取当前前台 app\n".data(using: .utf8)!)
    exit(1)
}

let priorPid = prior.processIdentifier
let priorName = prior.localizedName ?? "unknown"

FileHandle.standardError.write("focus-guard: 保护 '\(priorName)' (pid \(priorPid)) \(secs)s\n".data(using: .utf8)!)

let center = ws.notificationCenter

// 订阅焦点激活通知：任何非 prior 的 app 抢焦点，立即切回
let observer = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil) { n in
    guard let info = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
    if info.processIdentifier != priorPid {
        prior.activate(options: [.activateAllWindows])
        FileHandle.standardError.write("focus-guard: 拦截 \(info.localizedName ?? "?") 抢焦点，切回 \(priorName)\n".data(using: .utf8)!)
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
