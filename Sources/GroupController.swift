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
    /// 最后一次用户在该浮窗内活动的时间（自动关闭的判据）
    private var lastActivity = Date.distantPast
    /// 显示前的前台 App（隐藏时把系统焦点还给它）
    private var restoreApp: NSRunningApplication?
    /// 上次隐藏时抓取的网页焦点/滚动位置（{selector, scrollX, scrollY}）
    private var lastFocusInfo: [String: Any]?

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
    }

    // MARK: - 显示 / 隐藏 / 关闭

    func show(rememberedFrame frame: FrameSnapshot?) {
        // 记录显示前的前台 App，隐藏时把系统焦点还给它
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Config.bundleIdentifier {
            restoreApp = front
        }
        createWindowIfNeeded(rememberedFrame: frame)
        guard let w = window else { return }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        loadCurrentSiteIfChanged()
        lastActivity = Date()   // 呼出即视为开始新的闲置计时
        // 恢复网页内上次的焦点/滚动位置（页面没加载完时 didFinish 会再恢复一次）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.restoreFocusAndScroll()
        }
    }

    func hide() {
        captureFocusPosition()   // 隐藏前抓取网页内焦点/滚动位置
        window?.orderOut(nil)
        storeFrame()
        restoreFrontmostApp()     // 把系统焦点还给显示前的 App
    }

    func dispose() {
        captureFocusPosition()
        storeFrame()
        window?.orderOut(nil)
        webView = nil
        window = nil
        // 关键：下次重新创建 WebView 时必须重新加载当前网址，
        // 否则 loadCurrentSiteIfChanged() 会认为“网址没变”而跳过加载 → 白屏
        loadedURL = nil
        restoreFrontmostApp()
    }

    /// 窗口内发生交互（点击/滚动/输入/拖动/缩放/切站等）→ 刷新最后活动时间
    func noteInteraction() {
        if window?.isVisible == true {
            lastActivity = Date()
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
        noteInteraction()
    }

    /// 直接切到某个网址（供设置或外部调用）；返回是否成功
    @discardableResult
    func switchSite(to siteIndex: Int) -> Bool {
        guard config.sites.indices.contains(siteIndex) else { return false }
        config.activeSiteIndex = siteIndex
        onActiveSiteChanged(id, siteIndex)
        window?.title = titleText()
        loadCurrentSiteIfChanged()
        noteInteraction()
        return true
    }

    // MARK: - 闲置自动关闭
    // 语义说明：浮窗闲置满 N 分钟，不是简单“隐藏”，而是【彻底关闭并释放网页内存】；
    // 需要时再用快捷键呼出，会回到原位置、原网站（重新加载）。
    // 实现：不依赖单个长计时器，而是由 Manager 的“看门狗”每分钟轮询本方法。

    private func effectiveIdle() -> Int {
        config.effectiveIdle(global: globalIdle)
    }

    /// 看门狗调用：距最后一次活动超过阈值则彻底关闭
    func checkAutoClose(now: Date) {
        guard window?.isVisible == true else { return }
        let minutes = effectiveIdle()
        guard minutes > 0 else { return }   // 0/负数 = 不自动关闭

        // --idlefast：调试用，把“分钟”按“秒”当阈值，快速验证自动关闭
        let debugFast = ProcessInfo.processInfo.arguments.contains("--idlefast")
        let threshold: TimeInterval = debugFast ? TimeInterval(minutes) : TimeInterval(minutes * 60)

        if now.timeIntervalSince(lastActivity) >= threshold {
            let name = config.name
            let mins = minutes
            dispose()
            postNotification("「\(name)」已自动关闭（\(mins) 分钟未使用），已释放内存")
        }
    }

    /// 刷新当前浮窗页面（重载当前网址）
    func reloadCurrentSite() {
        guard window != nil, let wv = webView else { return }
        wv.reload()
        noteInteraction()
    }

    // MARK: - 页面缩放（⌘+ / ⌘- / ⌘0）

    /// 按倍数放大/缩小页面（如 1.1 放大、1/1.1 缩小）
    func adjustZoom(_ factor: CGFloat) {
        guard let wv = webView, window != nil else { return }
        let base = wv.magnification == 0 ? 1.0 : wv.magnification
        wv.setMagnification(base * factor,
                            centeredAt: NSPoint(x: wv.bounds.midX, y: wv.bounds.midY))
        noteInteraction()
    }

    func resetZoom() {
        guard let wv = webView else { return }
        wv.setMagnification(1.0, centeredAt: NSPoint(x: wv.bounds.midX, y: wv.bounds.midY))
        noteInteraction()
    }

    // MARK: - 焦点位置记忆
    // 打开弹窗时恢复到上次网页内焦点（文本框等）+ 页面滚动位置；
    // 隐藏弹窗时把系统焦点还给显示前正在使用的 App。

    /// 抓取当前网页内的焦点元素（稳定选择器）与滚动位置，供下次打开时恢复
    private func captureFocusPosition() {
        guard let wv = webView, window?.isVisible == true else { return }
        let js = """
        (function(){
          try {
            var el = document.activeElement;
            var body = document.body;
            if (!el || el === body || el === document.documentElement) {
              return {hasFocus:false, selector:null, scrollX:window.scrollX, scrollY:window.scrollY};
            }
            var path = [];
            var node = el;
            while (node && node.nodeType === 1 && node !== body && node !== document.documentElement) {
              var sel = node.tagName.toLowerCase();
              if (node.id) { sel += '#' + node.id; path.unshift(sel); break; }
              var parent = node.parentElement;
              if (parent) {
                var kids = Array.prototype.slice.call(parent.children).filter(function(c){ return c.tagName === node.tagName; });
                if (kids.length > 1) { sel += ':nth-of-type(' + (kids.indexOf(node) + 1) + ')'; }
              }
              path.unshift(sel);
              node = parent;
            }
            return {hasFocus:true, selector: path.join(' > ') || el.tagName.toLowerCase(), scrollX:window.scrollX, scrollY:window.scrollY};
          } catch(e) {
            return {hasFocus:false, selector:null, scrollX:window.scrollX, scrollY:window.scrollY};
          }
        })()
        """
        wv.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self else { return }
            if let dict = result as? [String: Any] {
                self.lastFocusInfo = dict
            }
        }
    }

    /// 恢复上次的滚动位置与网页内焦点
    private func restoreFocusAndScroll() {
        guard window?.isVisible == true, let wv = webView, let info = lastFocusInfo else { return }
        let selector = (info["selector"] as? String) ?? ""
        let sx = (info["scrollX"] as? NSNumber)?.doubleValue
        let sy = (info["scrollY"] as? NSNumber)?.doubleValue
        let selJSON = jsStringLiteral(selector)
        let sxJS = sx.map { "\($0)" } ?? "null"
        let syJS = sy.map { "\($0)" } ?? "null"
        let js = """
        (function(){
          if (\(sxJS) !== null && \(syJS) !== null) {
            try { window.scrollTo(\(sxJS), \(syJS)); } catch(e) {}
          }
          if (\(selJSON)) {
            var el = null;
            try { el = document.querySelector(\(selJSON)); } catch(e) {}
            if (el) {
              try { el.focus({preventScroll:true}); } catch(e) { try { el.focus(); } catch(e2){} }
            }
          }
        })()
        """
        wv.evaluateJavaScript(js, completionHandler: nil)
    }

    /// 把系统焦点还给显示前的 App（仅在焦点仍在我们这边时才归还）
    private func restoreFrontmostApp() {
        guard let app = restoreApp else { return }
        restoreApp = nil
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Config.bundleIdentifier {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    /// 把 Swift 字符串转成 JS 字符串字面量（安全转义）
    private func jsStringLiteral(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    // MARK: - 窗口创建

    private func createWindowIfNeeded(rememberedFrame remembered: FrameSnapshot?) {
        guard window == nil else { return }
        // 新窗口 = 全新 WebView，必须强制加载当前网址
        loadedURL = nil

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

        // B站页面清理（他律模式）：对 bilibili.com 各页面注入清理脚本，
        // 隐藏推荐流/相关推荐/娱乐入口，保留搜索、播放器与评论区
        let config = WKWebViewConfiguration()
        if let cleanJS = Self.biliCleanScript {
            config.userContentController.addUserScript(
                WKUserScript(source: cleanJS,
                             injectionTime: .atDocumentStart,
                             forMainFrameOnly: true))
        }
        let wv = WKWebView(frame: .zero, configuration: config)
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

    private static var biliCleanScript: String? {
        guard let url = Bundle.main.url(forResource: "bilibiliClean", withExtension: "js"),
              let s = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return s
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
        noteInteraction()   // 拖动窗口也算“活动”
    }

    func windowDidResize(_ notification: Notification) {
        guard let w = window, w.isVisible else { return }
        onFrameChanged(id, FrameSnapshot(from: w.frame))
        noteInteraction()   // 缩放窗口也算“活动”
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


    // MARK: - 网页进程崩溃/被系统终止后的自愈
    // B 站这类重页面在 8GB 内存的机器上偶尔会被 WebContent 进程杀/崩，
    // 重新加载而不是一直白屏。

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // 清掉“已加载”缓存，触发重新加载当前网址
        loadedURL = nil
        loadCurrentSiteIfChanged()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 页面（重新）加载完成 → 恢复上次的焦点/滚动位置
        restoreFocusAndScroll()
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
