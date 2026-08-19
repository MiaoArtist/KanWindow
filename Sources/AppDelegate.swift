import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var manager: PaneManager!
    private var statusItem: NSStatusItem!
    private var settingsController: SettingsWindowController?
    private var trustPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        manager = PaneManager(settings: SettingsStore.load())
        manager.onSettingsChanged = { [weak self] in
            self?.rebuildMenu()
        }

        setupStatusItem()
        requestNotificationPermission()

        if GlobalHotKey.isTrusted() {
            manager.applyHotkeys()
        } else {
            showAccessibilityAlert()
            scheduleTrustPoll()
        }
    }

    // MARK: - 状态栏菜单

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill",
                                   accessibilityDescription: Config.appName)
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()

        menu.addItem(switchItem(action: manager.settings.dAction, key: "⌥⌘D", selector: #selector(runDAction)))
        menu.addItem(switchItem(action: manager.settings.eAction, key: "⌥⌘E", selector: #selector(runEAction)))
        menu.addItem(NSMenuItem.separator())

        // 每个浮窗：显示 ⇄ 隐藏
        for pane in manager.enabledPanes {
            let title = manager.isPaneVisible(pane.id) ? "隐藏「\(pane.name)」" : "显示「\(pane.name)」"
            menu.addItem(actionItem(title: title) { [weak self] in
                self?.manager.showPane(id: pane.id)
            })
        }
        menu.addItem(NSMenuItem.separator())

        menu.addItem(actionItem(title: "显示全部浮窗") { [weak self] in
            self?.manager.showAll()
        })
        menu.addItem(actionItem(title: "隐藏全部浮窗") { [weak self] in
            self?.manager.hideAll()
        })
        menu.addItem(NSMenuItem.separator())

        menu.addItem(actionItem(title: "设置…", shortcut: ",") { [weak self] in
            self?.openSettings()
        })
        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "退出 \(Config.appName)", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// D/E 切换动作的菜单项（标题+提示随当前配置变化）
    private func switchItem(action: GlobalSwitchAction, key: String, selector: Selector) -> NSMenuItem {
        let title: String
        var tip = "\(key): "
        switch action {
        case .next:
            title = "下一个浮窗（\(key)）"
            tip += "依次切到下一个浮窗"
        case .previous:
            title = "上一个浮窗（\(key)）"
            tip += "依次切到上一个浮窗"
        case .specific(let id):
            let name = manager.settings.panes.first { $0.id == id }?.name ?? "浮窗"
            title = "切到「\(name)」（\(key)）"
            tip += "直接切到「\(name)」"
        case .none:
            title = "无动作（\(key)）"
            tip += "未绑定动作"
        }
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.toolTip = tip
        return item
    }

    private func actionItem(title: String, shortcut: String = "", _ handler: @escaping () -> Void) -> NSMenuItem {
        let target = ClosureActionTarget(handler: handler)
        let item = NSMenuItem(title: title, action: #selector(ClosureActionTarget.run), keyEquivalent: shortcut)
        item.target = target
        return item
    }

    // MARK: - 菜单动作

    @objc private func runDAction() { manager.perform(manager.settings.dAction) }
    @objc private func runEAction() { manager.perform(manager.settings.eAction) }
    @objc private func quitClicked() {
        manager.saveAllFrames()
        NSApp.terminate(nil)
    }

    private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(manager: manager)
        }
        settingsController?.show()
    }

    // MARK: - 辅助功能权限

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "需要「辅助功能」权限"
        alert.informativeText = "全局快捷键（⌥Space / ⌥⌘D / ⌥⌘E 等）需要「辅助功能」权限，才能在你使用其它 App 时生效。\n\n请在 系统设置 → 隐私与安全性 → 辅助功能 里勾选 \(Config.appName)，勾选后我会自动启用快捷键。\n（未勾选前，仍可用状态栏菜单呼出浮窗、打开设置。）"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "知道了")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func scheduleTrustPoll() {
        trustPollTimer?.invalidate()
        trustPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            if GlobalHotKey.isTrusted() {
                timer.invalidate()
                self.trustPollTimer = nil
                self.manager.applyHotkeys()
                self.flashStatus()
            }
        }
    }

    private func flashStatus() {
        guard let button = statusItem.button else { return }
        let original = button.image
        button.image = nil
        button.title = "✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            button.title = ""
            button.image = original
        }
    }

    // MARK: - 通知

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}

/// 把纯 Swift 闭包包成 NSMenuItem 的 target
private final class ClosureActionTarget: NSObject {
    private let handler: () -> Void
    init(handler: @escaping () -> Void) {
        self.handler = handler
    }
    @objc func run() { handler() }
}
