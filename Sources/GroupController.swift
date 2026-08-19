import AppKit
import WebKit
import UserNotifications

/// 网址组的悬浮窗：一个组 = 一个窗口，组内多个网址在这个窗口里切换。
/// 窗口懒创建（第一次 show 才建），停用/删除时释放。
final class GroupController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {

    let id: UUID
    private var config: GroupConfig
    private var globalIdle: Int

    private(set) var window: NSWindow?
    private var webView: WKWebView?
    private var loadedURL: String?
    private var idleTimer: Timer?

    private let onFrameChanged: (UUID, FrameSnapshot) -> Void
    private let onActiveSiteChanged: (UUID, Int) -> Void

    var isVisible: Bool { window?.isVisible ?? false }

    init(config: GroupConfig,
         globalIdle: Int,
         onFrameChanged: @escaping (UUID, FrameSnapshot) -> Void,
         onActiveSiteChanged: @escaping (UUID, Int) -> Void) {
        self.id = config.id
        self.config = config
        self.globalIdle = globalIdle
        self.onFrameChanged = onFrameChanged
        self.onActiveSiteChanged = onActiveSiteChanged
        super.init()
    }

    // MARK: - 配置同步

    func update(_ config: GroupConfig, globalIdle: Int) {
        self.config = config
        self.globalIdle = globalIdle
        window?.title = titleText()
        if webView != nil {
            loadCurrentSiteIfChanged()
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
        loadCurrentSiteIfChanged()
        startIdle()
    }

    func hide() {
        window?.orderOut(nil)
        stopIdle()
        storeFrame()
    }

    func dispose() {
        stopIdle()
        storeFrame()
        window?.orderOut(nil)
        webView = nil
        window = nil
    }

    func noteInteraction() {
        if window?.isVisible == true {
            startIdle()
        }
    }

    // MARK: - 组内切换网址

    /// 在组内上/下切换（顺/逆序循环）
    func switchSite(by offset: Int) {
        guard config.sites.count > 0 else { return }
        let count = config.sites.count
        let next = ((config.safeActiveIndex + offset) % count + count) % count
        config.activeSiteIndex = next
        onActiveSiteChanged(id, next)
        window?.title = titleText()
        loadCurrentSiteIfChanged()
        restartIdle()
    }

    /// 直接切到某个网址（供设置或外部调用）；返回是否成功
    @discardableResult
    func switchSite(to siteIndex: Int) -> Bool {
        guard config.sites.indices.contains(siteIndex) else { return false }
        config.activeSiteIndex = siteIndex
        onActiveSiteChanged(id, siteIndex)
        window?.title = titleText()
        loadCurrentSiteIfChanged()
        restartIdle()
        return true
    }

    // MARK: - 闲置自动关闭
    // 语义说明：浮窗闲置满 N 分钟，不是简单“隐藏”，而是【彻底关闭并释放网页内存】；
    // 需要时再用快捷键呼出，会回到原位置、原网站（重新加载）。

    private func effectiveIdle() -> Int {
        config.effectiveIdle(global: globalIdle)
    }

    private func startIdle() {
        stopIdle()
        let minutes = effectiveIdle()
        guard minutes > 0 else { return }   // 0/负数 = 不自动关闭

        let name = config.name
        let mins = minutes
        idleTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60),
                                         repeats: false) { [weak self] _ in
            guard let self = self, self.window?.isVisible == true else { return }
            self.dispose()
            self.postNotification("「\(name)」已自动关闭（\(mins) 分钟未使用），已释放内存")
        }
    }

    /// 刷新当前浮窗页面（重载当前网址）
    func reloadCurrentSite() {
        guard window != nil, let wv = webView else { return }
        wv.reload()
        restartIdle()
    }

    // MARK: - 页面缩放（⌘+ / ⌘- / ⌘0）

    /// 按倍数放大/缩小页面（如 1.1 放大、1/1.1 缩小）
    func adjustZoom(_ factor: CGFloat) {
        guard let wv = webView, window != nil else { return }
        let base = wv.magnification == 0 ? 1.0 : wv.magnification
        wv.setMagnification(base * factor,
                            centeredAt: NSPoint(x: wv.bounds.midX, y: wv.bounds.midY))
        restartIdle()
    }

    func resetZoom() {
        guard let wv = webView else { return }
        wv.setMagnification(1.0, centeredAt: NSPoint(x: wv.bounds.midX, y: wv.bounds.midY))
        restartIdle()
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
            contentRect: NSRect(x: 0, y: 0,
                                width: Config.defaultWindowSize.width,
                                height: Config.defaultWindowSize.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        w.title = titleText()
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
        wv.customUserAgent = Config.userAgent   // 伪装较新 Safari，解决部分站点“浏览器版本过低”
        wv.navigationDelegate = self
        wv.uiDelegate = self
        w.contentView = wv
        self.webView = wv

        if let f = remembered, Self.isOnAnyScreen(f.rect) {
            w.setFrame(f.rect, display: false)
        } else {
            center(w)
        }
        self.window = w
    }

    private func loadCurrentSiteIfChanged() {
        guard let site = config.activeSite, !site.url.isEmpty, let url = URL(string: site.url) else { return }
        if loadedURL == site.url { return }
        loadedURL = site.url
        webView?.load(URLRequest(url: url))
    }

    private func titleText() -> String {
        let siteName = config.activeSite?.name
        return siteName.map { "\(config.name) · \($0)" } ?? config.name
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

    func windowDidMove(_ notification: Notification) {
        guard let w = window, w.isVisible else { return }
        onFrameChanged(id, FrameSnapshot(from: w.frame))
    }

    func windowDidResize(_ notification: Notification) {
        guard let w = window, w.isVisible else { return }
        onFrameChanged(id, FrameSnapshot(from: w.frame))
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    // MARK: - 新窗口 / 新标签页处理（target=_blank / window.open 的链接点不进去的问题）

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // 不另开窗口：把新标签页请求交给当前浮窗直接加载
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
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
