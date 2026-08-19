import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var manager: GroupManager!
    private var statusItem: NSStatusItem!
    private var settingsController: SettingsWindowController?
    private var trustPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        manager = GroupManager(settings: SettingsStore.load())
        manager.onSettingsChanged = { [weak self] in
            self?.rebuildMenu()
        }

        buildMainMenu()          // 编辑菜单 → 让 WebView 文本框能 ⌘C/⌘V/⌘X/⌘A
        setupStatusItem()
        requestNotificationPermission()

        if GlobalHotKey.isTrusted() {
            manager.applyHotkeys()
        } else {
            showAccessibilityAlert()
            scheduleTrustPoll()
        }
    }

    // MARK: - 主菜单（粘贴修复：没有 Edit 菜单时 WKWebView 里 ⌘V 无效）

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu

        editMenu.addItem(textEditAction("撤销", selector: Selector(("undo:")), key: "z", shifted: false))
        editMenu.addItem(textEditAction("重做", selector: Selector(("redo:")), key: "z", shifted: true))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(textEditAction("剪切", selector: #selector(NSText.cut(_:)), key: "x", shifted: false))
        editMenu.addItem(textEditAction("复制", selector: #selector(NSText.copy(_:)), key: "c", shifted: false))
        editMenu.addItem(textEditAction("粘贴", selector: #selector(NSText.paste(_:)), key: "v", shifted: false))
        editMenu.addItem(textEditAction("全选", selector: #selector(NSText.selectAll(_:)), key: "a", shifted: false))

        NSApp.mainMenu = mainMenu
    }

    private func textEditAction(_ title: String, selector: Selector, key: String, shifted: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.keyEquivalentModifierMask = shifted ? [.command, .shift] : [.command]
        return item
    }

    // MARK: - 状态栏（左键=呼出/收起，右键=菜单）

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill",
                                   accessibilityDescription: Config.appName)
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp])
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    @objc private func statusClicked() {
        manager.toggle()
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

        for group in manager.enabledGroups {
            let title = manager.isGroupVisible(group.id) ? "隐藏「\(group.name)」" : "打开「\(group.name)」"
            menu.addItem(actionItem(title: title) { [weak self] in
                self?.manager.showGroup(id: group.id)
            })
        }
        menu.addItem(NSMenuItem.separator())

        menu.addItem(actionItem(title: "显示全部组") { [weak self] in
            self?.manager.showAll()
        })
        menu.addItem(actionItem(title: "隐藏全部组") { [weak self] in
            self?.manager.hideAll()
        })
        menu.addItem(NSMenuItem.separator())

        menu.addItem(actionItem(title: "设置…（⌘,）", shortcut: ",") { [weak self] in
            self?.openSettings()
        })
        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "退出 \(Config.appName)", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// D/E 动作菜单项（标题随配置变化）
    private func switchItem(action: GlobalSwitchAction, key: String, selector: Selector) -> NSMenuItem {
        let title: String
        switch action {
        case .next: title = "组内下一个网址（\(key)）"
        case .previous: title = "组内上一个网址（\(key)）"
        case .specificGroup(let id):
            let name = manager.settings.groups.first { $0.id == id }?.name ?? "组"
            title = "切到「\(name)」（\(key)）"
        case .none: title = "无动作（\(key)）"
        }
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
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
        alert.informativeText = "全局快捷键（⌥Space、⌥⌘D/E、各组快捷键）需要「辅助功能」权限才能在你使用其它 App 时生效。\n\n请在 系统设置 → 隐私与安全性 → 辅助功能 里勾选 \(Config.appName)，勾选后我会自动启用快捷键。\n（未勾选前仍可用状态栏呼出浮窗、打开设置。）"
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
