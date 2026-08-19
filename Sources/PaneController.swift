import AppKit
import WebKit
import UserNotifications

/// 单个悬浮窗：独立窗口 + WebView + 独立闲置计时 + 位置/尺寸记忆。
/// 窗口懒创建（第一次 show 时才建），停用/删除时释放。
final class PaneController: NSObject, NSWindowDelegate, WKNavigationDelegate {

    let id: UUID
    private var config: PaneConfig
    private var globalIdle: Int

    /// 懒创建的窗口与 WebView
    private(set) var window: NSWindow?
    private var webView: WKWebView?
    private var loadedURL: String?

    private var idleTimer: Timer?

    /// 窗口位置/尺寸变动 → 交给 Manager 存进设置
    private let onFrameChanged: (UUID, FrameSnapshot) -> Void
    /// 窗口第一次创建时的初始位置（中心）缓存，避免每次 show 重置
    private var hasInitialFrame = false

    var isVisible: Bool { window?.isVisible ?? false }

    init(config: PaneConfig,
         globalIdle: Int,
         onFrameChanged: @escaping (UUID, FrameSnapshot) -> Void) {
        self.id = config.id
        self.config = config
        self.globalIdle = globalIdle
        self.onFrameChanged = onFrameChanged
        super.init()
    }

    /// 设置变化时同步最新配置
    func update(_ config: PaneConfig, globalIdle: Int) {
        let urlChanged = self.config.url != config.url
        self.config = config
        self.globalIdle = globalIdle

        window?.title = config.name

        if urlChanged, let wv = webView, !config.url.isEmpty, let target = URL(string: config.url) {
            loadedURL = config.url
            wv.load(URLRequest(url: target))
        }
        if window?.isVisible == true {
            restartIdle()
        }
    }

    // MARK: - 显示 / 隐藏

    func show(rememberedFrame frame: FrameSnapshot?) {
        createWindowIfNeeded(rememberedFrame: frame)
        guard let w = window else { return }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        startIdle()
    }

    func hide() {
        window?.orderOut(nil)
        stopIdle()
        storeFrame()
    }

    /// 停用/删除该浮窗时释放窗口与 WebView 资源
    func dispose() {
        stopIdle()
        storeFrame()
        window?.orderOut(nil)
        webView = nil
        window = nil
    }

    /// 窗口内发生了交互（点击/滚动/输入）
    func noteInteraction() {
        if window?.isVisible == true {
            startIdle()
        }
    }

    // MARK: - 闲置自动隐藏

    private func effectiveIdle() -> Int {
        config.effectiveIdle(global: globalIdle)
    }

    private func startIdle() {
        stopIdle()
        let minutes = effectiveIdle()
        guard minutes > 0 else { return }  // 0/负数 = 不自动隐藏

        let name = config.name
        let hideMins = minutes
        idleTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60),
                                         repeats: false) { [weak self] _ in
            guard let self = self, self.window?.isVisible == true else { return }
            self.hide()
            self.postNotification("「\(name)」已自动隐藏（\(hideMins) 分钟未使用）")
        }
    }

    private func restartIdle() {
        startIdle()
    }

    private func stopIdle() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    // MARK: - 窗口创建

    private func createWindowIfNeeded(rememberedFrame remembered: FrameSnapshot?) {
        guard window == nil else { return }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Config.defaultWindowSize.width,
                                height: Config.defaultWindowSize.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        w.title = config.name
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        w.animationBehavior = .utilityWindow
        w.isMovableByWindowBackground = true
        w.hidesOnDeactivate = false
        w.isRestorable = false
        w.delegate = self

        let wv = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        wv.allowsMagnification = true
        wv.navigationDelegate = self
        w.contentView = wv
        self.webView = wv

        // 位置：优先用户记得的；否则居中
        if let f = remembered, Self.isOnAnyScreen(f.rect) {
            w.setFrame(f.rect, display: false)
        } else {
            center(w)
        }
        hasInitialFrame = true
        self.window = w

        loadCurrentURL()
    }

    private func loadCurrentURL() {
        guard !config.url.isEmpty, let url = URL(string: config.url) else { return }
        loadedURL = config.url
        webView?.load(URLRequest(url: url))
    }

    private func center(_ w: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = w.frame.size
        let x = visible.origin.x + (visible.width - size.width) / 2
        let y = visible.origin.y + (visible.height - size.height) / 2
        w.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
    }

    private static func isOnAnyScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { $0.frame.intersects(frame) }
    }

    // MARK: - 位置记忆

    private func storeFrame() {
        guard let w = window else { return }
        onFrameChanged(id, FrameSnapshot(from: w.frame))
    }

    private func currentFrame(_ w: NSWindow) -> FrameSnapshot {
        FrameSnapshot(from: w.frame)
    }

    // MARK: - 窗口行为

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    func windowDidMove(_ notification: Notification) {
        guard let w = window, w.isVisible else { return }
        onFrameChanged(id, currentFrame(w))
    }

    func windowDidResize(_ notification: Notification) {
        guard let w = window, w.isVisible else { return }
        onFrameChanged(id, currentFrame(w))
    }

    // MARK: - 标题

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 标题保留浮窗名（多开时一眼认出是谁）
    }

    // MARK: - 通知

    private func postNotification(_ body: String) {
        let content = UNMutableNotificationContent()
        content.title = Config.appName
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
