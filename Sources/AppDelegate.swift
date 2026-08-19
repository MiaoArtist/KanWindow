import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var popup: PopupWindowController!
    private var statusItem: NSStatusItem!
    private var trustPollTimer: Timer?
    private var hotKeysRegistered = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        popup = PopupWindowController(size: NSSize(width: Config.windowWidth, height: Config.windowHeight))
        setupStatusItem()
        requestNotificationPermissionIfNeeded()

        if GlobalHotKey.isTrusted() {
            registerHotKeys()
        } else {
            showAccessibilityAlert()
            scheduleTrustPoll()
        }
    }

    // MARK: - 状态栏菜单（无 Dock 图标时唯一的常驻入口）

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill",
                                   accessibilityDescription: Config.appName)
        }

        let menu = NSMenu()

        let toggleItem = NSMenuItem(title: "显示 / 隐藏弹窗（⌥Space）",
                                    action: #selector(toggleClicked), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let doubaoItem = NSMenuItem(title: "切换到 豆包（⌥⌘D）",
                                    action: #selector(switchToDoubao), keyEquivalent: "")
        doubaoItem.target = self
        menu.addItem(doubaoItem)

        let deepseekItem = NSMenuItem(title: "切换到 DeepSeek（⌥⌘E）",
                                      action: #selector(switchToDeepSeek), keyEquivalent: "")
        deepseekItem.target = self
        menu.addItem(deepseekItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出 \(Config.appName)", action: #selector(quitClicked), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    // MARK: - 全局热键

    private func registerHotKeys() {
        guard !hotKeysRegistered else { return }
        hotKeysRegistered = true

        GlobalHotKey.register(keyCode: Config.HotKey.toggleKeyCode,
                              modifiers: Config.HotKey.toggleModifiers,
                              id: 1) { [weak self] in
            self?.popup.toggle()
        }
        GlobalHotKey.register(keyCode: Config.HotKey.doubaoKeyCode,
                              modifiers: Config.HotKey.switchModifiers,
                              id: 2) { [weak self] in
            self?.popup.switchToSite(name: Config.defaultSiteName, url: Config.doubaoURL)
        }
        GlobalHotKey.register(keyCode: Config.HotKey.deepseekKeyCode,
                              modifiers: Config.HotKey.switchModifiers,
                              id: 3) { [weak self] in
            self?.popup.switchToSite(name: "DeepSeek", url: Config.deepseekURL)
        }
        NSLog("全局热键已注册（⌥Space / ⌥⌘D / ⌥⌘E）")
    }

    // MARK: - 辅助功能权限

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "需要「辅助功能」权限"
        alert.informativeText = "全局快捷键（⌥Space 等）需要「辅助功能」权限才能在你使用其他 App 时生效。\n\n请在系统设置中勾选 \(Config.appName)，勾选后我会自动检测并启用快捷键。\n（在勾选之前，仍可通过状态栏菜单呼出弹窗。）"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "知道了")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    private func scheduleTrustPoll() {
        trustPollTimer?.invalidate()
        trustPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            if GlobalHotKey.isTrusted() {
                timer.invalidate()
                self.trustPollTimer = nil
                self.registerHotKeys()
                self.showStatusToast("已获取权限，全局快捷键已启用 ✓")
            }
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 通知权限

    private func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - 动作

    @objc private func toggleClicked() { popup.toggle() }
    @objc private func switchToDoubao() { popup.switchToSite(name: Config.defaultSiteName, url: Config.doubaoURL) }
    @objc private func switchToDeepSeek() { popup.switchToSite(name: "DeepSeek", url: Config.deepseekURL) }
    @objc private func quitClicked() { NSApp.terminate(nil) }

    private func showStatusToast(_ text: String) {
        guard let button = statusItem.button else { return }
        let original = button.image
        button.image = nil
        button.title = "✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            button.title = ""
            button.image = original
        }
        _ = text
    }
}
