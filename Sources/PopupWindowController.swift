import AppKit
import WebKit
import UserNotifications

/// 悬浮弹窗：一个永远浮在上层的 WebView 小窗口。
/// 职责：显示网页、随全局热键显示/隐藏、切换站点、15 分钟空闲自动隐藏。
final class PopupWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate {

    let window: NSWindow
    private let webView: WKWebView
    private var idleTimer: Timer?
    private var eventMonitor: Any?

    private var currentSiteName = "在线 AI 悬浮窗"
    private var didPositionOnce = false

    init(size: NSSize) {
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = Config.appName
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        window.animationBehavior = .utilityWindow
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.isRestorable = false

        let configuration = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true

        window.contentView = webView

        super.init()

        window.delegate = self
        webView.navigationDelegate = self

        centerWindow()
        loadSite(name: Config.defaultSiteName, url: Config.doubaoURL)
        startIdleTimer()
        installInteractionMonitor()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    // MARK: - 对外接口（供热键 / 菜单调用）

    /// ⌥Space：显示 ⇄ 隐藏
    func toggle() {
        if window.isVisible {
            hideWindow(reason: nil)
        } else {
            showWindow()
        }
    }

    /// 切到某站点并呼出
    func switchToSite(name: String, url: String) {
        loadSite(name: name, url: url)
        showWindow()
    }

    var isVisible: Bool { window.isVisible }

    // MARK: - 显示 / 隐藏

    func showWindow() {
        centerWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        startIdleTimer()
    }

    private func hideWindow(reason: String?) {
        window.orderOut(nil)
        stopIdleTimer()
        if let reason = reason {
            postNotification(reason)
        }
    }

    /// 15 分钟空闲自动隐藏
    private func autoHide() {
        if window.isVisible {
            hideWindow(reason: "「对\(currentSiteName)」已自动隐藏（\(Config.idleMinutes) 分钟未使用）")
        }
    }

    // MARK: - 页面加载

    /// 首次启动时把窗口放到主屏居中（之后保持用户拖过的位置）
    private func centerWindow() {
        guard !didPositionOnce, let screen = NSScreen.main else { return }
        didPositionOnce = true
        let visible = screen.visibleFrame
        let size = window.frame.size
        let x = visible.origin.x + (visible.width - size.width) / 2
        let y = visible.origin.y + (visible.height - size.height) / 2
        window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
    }

    private func loadSite(name: String, url: String) {
        currentSiteName = name
        window.title = name
        guard let target = URL(string: url) else { return }
        webView.load(URLRequest(url: target))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 页面标题回填到窗口标题（比站点名更具体）
        if let title = webView.title, !title.isEmpty {
            window.title = "\(currentSiteName) · \(title)"
        }
    }

    // MARK: - 闲置计时

    private func startIdleTimer() {
        stopIdleTimer()
        let interval = TimeInterval(max(Config.idleMinutes, 1) * 60)
        idleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.autoHide()
        }
    }

    private func stopIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    /// 应用窗口内的任何点击 / 滚动 / 按键都重置计时
    private func installInteractionMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]
        ) { [weak self] event in
            if self?.window.isVisible == true {
                self?.startIdleTimer()
            }
            return event
        }
    }

    // MARK: - 窗口行为

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 点红色关闭按钮 = 隐藏，不销毁窗口
        hideWindow(reason: nil)
        return false
    }

    // MARK: - 通知

    private func postNotification(_ body: String) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "在线 AI 悬浮窗"
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    // MARK: - 清理

    @objc private func applicationWillTerminate() {
        stopIdleTimer()
        NSEvent.removeMonitor(eventMonitor as Any)
    }
}
