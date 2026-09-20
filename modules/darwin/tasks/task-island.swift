import SwiftUI
import AppKit
import Combine
import Darwin

// MARK: - 任务灵动岛（观察者模式）
//
// 设计约束：任务执行与界面显示必须彻底解耦。
// launchd 的 user 域是 Background session，进程拿不到 WindowServer，画不出窗口；
// gui 域是 Aqua session，但只在存在图形登录会话时才存在。二者无法在同一个进程里兼得，
// 因此这里只做「观察者」：
//
//   task-<name>（user 域，跑不跑与界面无关）
//     ├─ 输出双写一份到 ~/Library/Logs/task-island/<name>.log
//     ├─ 触碰 <name>.marker（内容：pid + 规范日志路径）
//     └─ 正常执行任务本体，退出码与日志完全不受这里影响
//
//   task-island watch（gui 域，由 launchd WatchPaths 按需拉起）
//     ├─ 找到最新的 marker，从 0 开始跟随 <name>.log
//     ├─ 解析任务包装器自己打印的 "Finished (exit code: N)" 判定结束
//     └─ 展示状态/live 日志，成功自动收走，失败常驻到用户关闭

enum IslandPhase: Equatable {
    case running
    case success
    case failed
}

struct LogLine: Identifiable, Equatable {
    let id: Int
    let text: String
    let isError: Bool
}

// MARK: - 运行记录

struct RunRecord {
    let name: String
    let pid: Int32
    let canonicalLog: String
    let islandLog: String
    let started: Date

    /// 包装器 trap 写入的确定性退出码副档（内容为整数字符串；不存在 = 尚未结束）
    var exitFilePath: String {
        ((islandLog as NSString).deletingLastPathComponent as NSString).appendingPathComponent("\(name).exit")
    }

    /// 读取退出码副档；nil = 任务还没结束（或被 SIGKILL 永远不会有）
    func readExitCode() -> Int32? {
        guard let raw = try? String(contentsOfFile: exitFilePath, encoding: .utf8),
              let code = Int32(raw.trimmingCharacters(in: .whitespaces))
        else { return nil }
        return code
    }

    static func latest(in dir: String) -> RunRecord? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return nil }

        var newest: (path: String, date: Date)?
        for entry in entries where entry.hasSuffix(".marker") {
            let path = (dir as NSString).appendingPathComponent(entry)
            guard let date = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date else { continue }
            if newest == nil || date > newest!.date { newest = (path, date) }
        }
        guard let marker = newest else { return nil }

        let name = ((marker.path as NSString).lastPathComponent as NSString).deletingPathExtension
        let content = (try? String(contentsOfFile: marker.path, encoding: .utf8)) ?? ""
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 2, let pid = Int32(lines[0].trimmingCharacters(in: .whitespaces)) else { return nil }

        return RunRecord(
            name: name,
            pid: pid,
            canonicalLog: lines[1].trimmingCharacters(in: .whitespaces),
            islandLog: (dir as NSString).appendingPathComponent("\(name).log"),
            started: marker.date
        )
    }
}

// MARK: - 日志跟随

final class LogTailer {
    private let path: String
    private var offset: UInt64 = 0
    private var remainder = Data()

    init(path: String) {
        self.path = path
    }

    /// 返回自上次调用以来的新增整行；文件被截断（新一轮运行）时自动从头重新跟随
    func poll() -> [String] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else { return [] }
        if size < offset {
            offset = 0
            remainder.removeAll()
        }
        guard size > offset else { return [] }

        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return [] }
        offset += UInt64(data.count)

        var lines: [String] = []
        remainder.append(data)
        while let newline = remainder.firstIndex(of: 0x0A) {
            let lineData = remainder[remainder.startIndex..<newline]
            remainder.removeSubrange(remainder.startIndex...newline)
            lines.append(String(decoding: lineData, as: UTF8.self))
        }
        return lines
    }
}

// MARK: - 状态模型

@MainActor
final class IslandViewModel: ObservableObject {
    @Published var phase: IslandPhase = .running
    @Published var taskName = "task"
    @Published var elapsed: Double = 0
    @Published var exitCode: Int32 = 0
    @Published var failureReason = ""
    @Published var logPath: String?
    @Published var logLines: [LogLine] = []
    @Published var isExpanded = false
    @Published var isHovering = false
    @Published var containerSize: CGSize = .zero

    var onDismiss: (() -> Void)?

    private var ticker: Timer?
    private var pendingDismiss: DispatchWorkItem?
    private var nextLineID = 0
    private let maxLines = 1500

    func begin(taskName: String, logPath: String?, startedAt: Date) {
        self.taskName = taskName
        self.logPath = logPath
        phase = .running
        elapsed = max(0, Date().timeIntervalSince(startedAt))
        exitCode = 0
        failureReason = ""
        logLines = []
        nextLineID = 0
        isExpanded = false
        startTicker(since: startedAt)
    }

    func finishSuccess(duration: Double) {
        stopTicker()
        elapsed = duration
        phase = .success
        scheduleDismiss()
    }

    func finishFailure(code: Int32, reason: String, duration: Double) {
        stopTicker()
        elapsed = duration
        phase = .failed
        exitCode = code
        failureReason = reason
        cancelDismiss()
    }

    func append(_ incoming: [(String, Bool)]) {
        guard !incoming.isEmpty else { return }
        var ready: [LogLine] = []
        ready.reserveCapacity(incoming.count)
        for (raw, isError) in incoming {
            var text = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if text.count > 4000 { text = String(text.prefix(4000)) + " …" }
            ready.append(LogLine(id: nextLineID, text: text, isError: isError))
            nextLineID += 1
        }
        logLines.append(contentsOf: ready)
        if logLines.count > maxLines + 250 {
            logLines.removeFirst(logLines.count - maxLines)
        }
    }

    var lastMeaningfulLine: String? {
        for line in logLines.reversed() where !line.text.trimmingCharacters(in: .whitespaces).isEmpty {
            return line.text
        }
        return nil
    }

    /// 最后一条真实输出（跳过包装器自己打印的 ===== 分隔行），用于失败原因摘要
    var lastDiagnosticLine: String? {
        for line in logLines.reversed() {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            if text.isEmpty || text.contains("=====") { continue }
            return text
        }
        return nil
    }

    var logFileAvailable: Bool {
        guard let path = logPath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    func toggleExpanded() {
        isExpanded.toggle()
        if isExpanded {
            cancelDismiss()
        } else if phase == .success {
            scheduleDismiss()
        }
    }

    func close() {
        cancelDismiss()
        onDismiss?()
    }

    func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        isHovering = hovering
        if hovering {
            cancelDismiss()
        } else if phase == .success && !isExpanded {
            scheduleDismiss()
        }
    }

    private func startTicker(since start: Date) {
        stopTicker()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .running else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func scheduleDismiss() {
        cancelDismiss()
        guard phase == .success, !isExpanded, !isHovering else { return }
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.close() }
        }
        pendingDismiss = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
    }

    private func cancelDismiss() {
        pendingDismiss?.cancel()
        pendingDismiss = nil
    }
}

// MARK: - SwiftUI 视图

struct DynamicIslandView: View {
    @ObservedObject var vm: IslandViewModel
    @State private var spin = false

    private let compactWidth: CGFloat = 380
    private let failedWidth: CGFloat = 480
    private let expandedWidth: CGFloat = 560
    private let headerHeight: CGFloat = 50
    private let maxLogHeight: CGFloat = 176
    private let footerHeight: CGFloat = 34

    /// 日志区高度随行数增长（空日志不留空洞），超过上限后改为内部滚动
    private var logHeight: CGFloat {
        let content = CGFloat(vm.logLines.count) * 12.5 + 12
        return min(maxLogHeight, max(64, content))
    }

    private var containerWidth: CGFloat {
        if vm.isExpanded { return expandedWidth }
        return vm.phase == .failed ? failedWidth : compactWidth
    }

    private let successColor = Color(red: 0.30, green: 0.85, blue: 0.42)
    private let failureColor = Color(red: 0.95, green: 0.32, blue: 0.30)
    private let runningColor = Color(red: 0.35, green: 0.65, blue: 1.00)

    var body: some View {
        VStack(spacing: 0) {
            header
            if vm.isExpanded {
                divider
                logBody
                    .frame(height: logHeight)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.06),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                divider
                logFooter
            }
        }
        .frame(width: containerWidth)
        .background(
            ZStack {
                islandShape.fill(Color.black)
                islandShape.fill(
                    LinearGradient(colors: [Color.white.opacity(0.05), .clear], startPoint: .top, endPoint: .bottom)
                )
            }
        )
        .clipShape(islandShape)
        .overlay(islandShape.strokeBorder(borderColor, lineWidth: 1))
        .onGeometryChange(for: CGSize.self) { proxy in proxy.size } action: { size in
            vm.containerSize = size
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.80), value: vm.isExpanded)
        .animation(.spring(response: 0.38, dampingFraction: 0.80), value: vm.phase)
        .animation(.easeOut(duration: 0.18), value: logHeight)
        .onHover { vm.setHovering($0) }
    }

    // MARK: 形状

    private var islandShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: 0,
                bottomLeading: vm.isExpanded ? 28 : 22,
                bottomTrailing: vm.isExpanded ? 28 : 22,
                topTrailing: 0
            ),
            style: .continuous
        )
    }

    private var borderColor: Color {
        switch vm.phase {
        case .running: return Color.white.opacity(vm.isHovering ? 0.30 : 0.16)
        case .success: return successColor.opacity(0.35)
        case .failed: return failureColor.opacity(0.45)
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
    }

    // MARK: 头部（收起态就是胶囊本体，点击切换展开）

    private var header: some View {
        headerContent
            .padding(.horizontal, 16)
            .frame(height: headerHeight)
            .contentShape(Rectangle())
            .onTapGesture { vm.toggleExpanded() }
    }

    @ViewBuilder
    private var headerContent: some View {
        switch vm.phase {
        case .running: runningRow
        case .success: successRow
        case .failed: failedRow
        }
    }

    private var runningRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(runningColor)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .onAppear {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spin = true }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(vm.taskName)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text(vm.lastMeaningfulLine ?? "等待输出…")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 10)

            HStack(spacing: 9) {
                Text(String(format: "%.1fs", vm.elapsed))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.6))
                chevron
            }
        }
    }

    private var successRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(successColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(vm.taskName)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text(String(format: "执行完成 · 耗时 %.1fs", vm.elapsed))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(successColor.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            HStack(spacing: 9) {
                badge("0", background: successColor, foreground: .black)
                chevron
            }
        }
    }

    private var failedRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(failureColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(vm.taskName)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    badge("Exit \(vm.exitCode)", background: failureColor.opacity(0.85), foreground: .white)
                }
                Text(vm.failureReason)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(failureColor.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 10)
            chevron
        }
    }

    private func badge(_ text: String, background: Color, foreground: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(background)
            .clipShape(Capsule())
    }

    private var chevron: some View {
        Image(systemName: vm.isExpanded ? "chevron.up" : "chevron.down")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white.opacity(0.26))
    }

    // MARK: 日志区

    private var logBody: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if vm.logLines.isEmpty {
                        Text(vm.phase == .running ? "等待输出…" : "本次运行没有产生任何输出")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    ForEach(vm.logLines) { line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(color(for: line))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .onChange(of: vm.logLines.count) { _, _ in
                guard let last = vm.logLines.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func color(for line: LogLine) -> Color {
        if line.text.contains("=====") { return Color(red: 0.45, green: 0.72, blue: 1.00).opacity(0.85) }
        if line.isError { return Color(red: 1.00, green: 0.56, blue: 0.52) }
        return Color.white.opacity(0.78)
    }

    private var logFooter: some View {
        HStack(spacing: 16) {
            if vm.logFileAvailable {
                footerButton("doc.text.magnifyingglass", "打开日志文件") {
                    if let path = vm.logPath {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                }
            }
            footerButton("doc.on.doc", "复制全部") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(vm.logLines.map(\.text).joined(separator: "\n"), forType: .string)
            }

            Spacer(minLength: 8)

            Text("\(vm.logLines.count) 行")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.32))

            Button(action: { vm.close() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.10))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(.horizontal, 16)
        .frame(height: footerHeight)
    }

    private func footerButton(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.72))
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

// MARK: - 窗口（贴顶、透明、非激活、首次点击即可生效）

final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class IslandWindow: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = NSWindow.Level(Int(CGWindowLevelForKey(.mainMenuWindow)) + 150)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        isMovable = false
        ignoresMouseEvents = false
    }
}

// MARK: - 主控

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let vm = IslandViewModel()
    let args: [String]

    private var window: IslandWindow!
    private var sizeSub: AnyCancellable?
    private var tailer: LogTailer?
    private var pollTimer: Timer?
    private var record: RunRecord?
    private var watchDir = ""
    private var finished = false
    private var lockFD: Int32 = -1

    init(args: [String]) {
        self.args = args
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupWindow()
        start()
    }

    // MARK: 窗口

    private var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func setupWindow() {
        let initial = CGSize(width: 380, height: 50)
        let frame = targetScreen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let rect = NSRect(
            x: (frame.midX - initial.width / 2).rounded(),
            y: frame.maxY - initial.height,
            width: initial.width,
            height: initial.height
        )

        let panel = IslandWindow(frame: rect)
        let hosting = ClickThroughHostingView(rootView: DynamicIslandView(vm: vm))
        // 窗口几何完全由 applySize 控制：NSHostingView 自行改写窗口会让灵动岛偏离屏幕中线
        hosting.sizingOptions = []
        panel.contentView = hosting
        window = panel

        vm.onDismiss = { [weak self] in
            guard let self else { return }
            self.exitGracefully()
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 1
        }

        sizeSub = vm.$containerSize
            .removeDuplicates()
            .sink { [weak self] size in
                MainActor.assumeIsolated { self?.applySize(size) }
            }
    }

    private func applySize(_ size: CGSize) {
        guard size.width > 8, size.height > 8, let screen = targetScreen else { return }
        let w = ceil(size.width)
        let h = ceil(size.height)
        let frame = screen.frame
        let rect = NSRect(
            x: (frame.midX - w / 2).rounded(),
            y: frame.maxY - h,
            width: w,
            height: h
        )
        let current = window.frame
        if abs(current.width - w) < 0.5,
           abs(current.height - h) < 0.5,
           abs(current.origin.x - rect.origin.x) < 0.5,
           abs(current.origin.y - rect.origin.y) < 0.5 {
            return
        }
        window.setFrame(rect, display: true)
    }

    private func exitGracefully() {
        pollTimer?.invalidate()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            window.animator().alphaValue = 0
        }, completionHandler: {
            exit(0)
        })
    }

    // MARK: 入口分派

    private func start() {
        if let idx = args.firstIndex(of: "watch") {
            startWatch(Array(args.dropFirst(idx + 1)))
            return
        }
        if let idx = args.firstIndex(of: "demo") {
            let mode = args.count > idx + 1 ? args[idx + 1] : "logs"
            switch mode {
            case "success": runDemo(mode: .success)
            case "fail": runDemo(mode: .fail)
            default: runDemo(mode: .logs)
            }
            return
        }
        printUsage()
    }

    private func printUsage() {
        let usage = """
        task-island — 定时任务灵动岛状态显示（观察者）

        Usage:
          task-island watch [--dir <状态目录>]   跟随最近一次任务运行并展示（默认 ~/Library/Logs/task-island）
          task-island demo [success|fail|logs]  预览三种状态（默认 logs）

        由 launchd 拉起：任务在 user 域执行并触碰 marker，gui 域的本进程只负责观察与显示，
        任务执行、输出、退出码均不依赖本进程。
        """
        print(usage)
        exit(0)
    }

    // MARK: 观察模式

    private func startWatch(_ sub: [String]) {
        var dir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/task-island")
        if let idx = sub.firstIndex(of: "--dir"), sub.count > idx + 1 {
            dir = sub[idx + 1]
        }

        guard let found = RunRecord.latest(in: dir) else {
            FileHandle.standardError.write(Data("task-island: \(dir) 下没有运行记录\n".utf8))
            exit(0)
        }
        // 陈旧记录（例如目录发生无关变化导致的重入）不再重复展示
        guard Date().timeIntervalSince(found.started) < 120 else {
            FileHandle.standardError.write(Data("task-island: 最近一次运行已过去 \(Int(Date().timeIntervalSince(found.started)))s，跳过\n".utf8))
            exit(0)
        }
        // 同一时刻只保留一个灵动岛；后续触发直接退出（正在展示的那次已覆盖屏幕）
        guard acquireLock(dir: dir) else { exit(0) }

        watchDir = dir
        beginSession(found)
        poll()
    }

    private func beginSession(_ found: RunRecord) {
        record = found
        finished = false
        pollTimer?.invalidate() // 切换会重建 tailer，旧计时器回调持有的 self 已重入，停掉防止同轮重复 poll
        tailer = LogTailer(path: found.islandLog)
        vm.begin(taskName: found.name, logPath: found.canonicalLog, startedAt: found.started)
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func acquireLock(dir: String) -> Bool {
        let path = (dir as NSString).appendingPathComponent(".island.lock")
        lockFD = open(path, O_CREAT | O_RDWR, 0o644)
        // 目录不可写属于环境异常，降级并发展示比失败更难排查，直接拒绝启动
        guard lockFD >= 0 else {
            FileHandle.standardError.write(Data("task-island: 无法创建锁文件 \(path): errno=\(errno)\n".utf8))
            return false
        }
        return flock(lockFD, LOCK_EX | LOCK_NB) == 0
    }

    private func poll() {
        guard let record, let tailer else { return }

        // 任何时刻出现更新的运行都立即切换：一个灵动岛始终展示最新一次运行
        // （旧运行的结果被顶掉是既有语义；失败常驻只是「没有更新运行时」的停留策略）
        if let newer = RunRecord.latest(in: watchDir), newer.started > record.started {
            beginSession(newer)
            return
        }

        if finished { return }

        let lines = tailer.poll()
        if !lines.isEmpty {
            vm.append(lines.map { ($0, Self.isErrorLine($0)) })
            for line in lines where line.contains("Finished (exit code:") {
                if let code = Self.exitCode(in: line) {
                    finalize(code: code)
                    return
                }
            }
        }

        // 确定性通道：trap 写入的退出码副档。日志行经 tee 异步落盘有滞后，
        // 进程死亡检查有 pid 复用误判风险，两者都让位于这里
        if let code = record.readExitCode() {
            finalize(code: code)
            return
        }

        // 包装器被 SIGKILL 时永远不会有副档：宽限 2s 后依据进程存活判定，
        // 避免永远显示「执行中」；pid 复用会让 kill 误判存活，宽限是可接受的折衷
        if Date().timeIntervalSince(record.started) > 2, kill(record.pid, 0) != 0 {
            finalize(code: -1, reason: "任务已结束（未捕获退出码）")
        }
    }

    /// 真实日志的错误行约定：以 "!!" 开头（demo 与包装器输出共用）
    private static func isErrorLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("!!")
    }

    private static func exitCode(in line: String) -> Int32? {
        guard let range = line.range(of: "exit code: ") else { return nil }
        let digits = line[range.upperBound...].prefix { $0.isNumber }
        return Int32(digits)
    }

    private func finalize(code: Int32, reason: String? = nil) {
        guard !finished else { return }
        finished = true
        // 不停轮询：失败常驻期间要能切换到下一轮运行

        let duration = record.map { Date().timeIntervalSince($0.started) } ?? vm.elapsed
        if code == 0 {
            vm.finishSuccess(duration: duration)
        } else {
            let tail = reason ?? vm.lastDiagnosticLine ?? vm.lastMeaningfulLine ?? "退出码 \(code)"
            let trimmed = tail.count > 64 ? String(tail.suffix(64)) : tail
            vm.finishFailure(code: code, reason: trimmed, duration: duration)
        }
    }

    // MARK: 演示

    private enum DemoMode { case success, fail, logs }

    private func runDemo(mode: DemoMode) {
        let dir = NSTemporaryDirectory() + "task-island"
        let path = (dir as NSString).appendingPathComponent("demo.log")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let lines: [(String, Bool)] = mode == .logs ? demoLong : demoShort
        let duration = mode == .logs ? 0.45 : 0.35
        let failing = mode != .success
        let taskName = "demo-pi-ping"

        try? lines.map(\.0).joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
        vm.begin(taskName: taskName, logPath: path, startedAt: Date())

        if mode == .logs {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.vm.toggleExpanded()
            }
        }

        for (index, line) in lines.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * duration) { [weak self] in
                self?.vm.append([line])
            }
        }

        let total = Double(lines.count) * duration + 0.4
        DispatchQueue.main.asyncAfter(deadline: .now() + total) { [weak self] in
            guard let self else { return }
            if failing {
                self.vm.finishFailure(code: 1, reason: "HTTP 503 Service Unavailable", duration: total)
            } else {
                self.vm.finishSuccess(duration: total)
            }
        }
    }

    private var demoShort: [(String, Bool)] {
        [
            ("[00:00:01] ===== Task 'pi-ping' Started =====", false),
            ("pi: model=openai-codex/gpt-5.6-luna thinking=off", false),
            ("pi: session=offline prompt=\"hi\"", false),
            ("pi: request sent (tokens in=2)", false),
            ("pi: streaming response …", false),
            ("pi: response received in 1.6s (tokens out=14)", false),
            ("pi: done", false),
        ]
    }

    private var demoLong: [(String, Bool)] {
        [
            ("[00:00:01] ===== Task 'pi-ping' Started =====", false),
            ("pi: model=openai-codex/gpt-5.6-luna thinking=off", false),
            ("pi: session=offline prompt=\"hi\"", false),
            ("pi: tools=disabled skills=disabled extensions=disabled", false),
            ("pi: request sent (tokens in=2)", false),
            ("pi: streaming response …", false),
            ("pi: chunk 1/3 received", false),
            ("!! pi: chunk 2/3 stalled for 8.0s", true),
            ("!! pi: upstream returned 503 Service Unavailable", true),
            ("!! pi: retry 1/1 after 2s", true),
            ("pi: retry sent", false),
            ("!! pi: upstream returned 503 Service Unavailable", true),
            ("!! pi: giving up after 2 attempts", true),
            ("[00:00:14] ===== Task 'pi-ping' Finished (exit code: 1) =====", false),
        ]
    }
}

// MARK: - 启动

@main
struct IslandMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate(args: Array(CommandLine.arguments.dropFirst()))
        app.delegate = delegate
        app.run()
    }
}
