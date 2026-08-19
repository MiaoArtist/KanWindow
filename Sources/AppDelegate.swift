import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var manager: GroupManager!
    private var statusItem: NSStatusItem!
    private var settingsController: SettingsWindowController?
    private var trustPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        manager = GroupManager(settings: SettingsStore.load())

        buildMainMenu()          // App 菜单(⌘, 设置 / ⌘Q) + 编辑菜单(⌘V 粘贴修复)
        setupStatusItem()
        requestNotificationPermission()

        if GlobalHotKey.isTrusted() {
            manager.applyHotkeys()
        } else {
            showAccessibilityAlert()
            scheduleTrustPoll()
        }
    }

    // MARK: - 主菜单
    // ① App 菜单：让 ⌘,（设置）与 ⌘Q（退出）在应用活跃时全局可用
    // ② 编辑菜单：修复 WebView 文本框无法 ⌘C/⌘V/⌘X/⌘A 的问题
    // 注意：所有菜单项 target 一律用 self（AppDelegate 强生命周期），
    //       不用临时闭包对象当 target —— NSMenuItem.target 是弱引用，会被提前释放导致点了没反应。

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // App 菜单（放最前）
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: Config.appName)
        appItem.submenu = appMenu

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem.separator())
        let appQuit = NSMenuItem(title: "退出 \(Config.appName)", action: #selector(quitClicked), keyEquivalent: "q")
        appQuit.target = self
        appMenu.addItem(appQuit)

        // 编辑菜单
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

    // MARK: - 状态栏（左键=呼出弹窗，右键=弹菜单；不挂 menu，避免点击卡死）

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }

        if let icon = NSImage(named: "MenuBarIcon") {
            icon.isTemplate = true
            icon.size = NSSize(width: 18, height: 18)
            button.image = icon
        } else {
            button.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill",
                                   accessibilityDescription: Config.appName)
        }
        button.target = self
        button.action = #selector(statusClicked)
        // 左/右鼠标松开都发 action，自己在 action 里区分，从而不依赖 statusItem.menu
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || event?.type == .rightMouseDown
            || (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true)

        if isRightClick {
            // 每次现做一份新菜单，定位在图标处弹出（绝不在跟踪过程中改菜单）
            if let button = statusItem?.button, let w = button.window {
                let rect = w.convertToScreen(button.convert(button.bounds, to: nil))
                let menu = buildMenu()
                menu.popUp(positioning: nil, at: NSPoint(x: rect.minX, y: rect.minY), in: nil)
            }
        } else {
            manager.toggle()
        }
    }

    /// 现做一份右键菜单（全部项 target = self）
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // 找到 ⌥⌘D / ⌥⌘E 绑定的功能显示在顶部（跟随用户改的快捷键表）
        if let d = hotkeyItem(keyCode: Config.HotKey.switchKeyCodeD, keyDisplay: "⌥⌘D") {
            menu.addItem(d)
        }
        if let e = hotkeyItem(keyCode: Config.HotKey.switchKeyCodeE, keyDisplay: "⌥⌘E") {
            menu.addItem(e)
        }
        menu.addItem(NSMenuItem.separator())

        for group in manager.enabledGroups {
            // 切换至某组：切过去后，⌥Space / 左键点的就是这一组
            let item = NSMenuItem(title: "切换至「\(group.name)」", action: #selector(menuOpenGroup(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = group.id
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())

        let showAll = NSMenuItem(title: "显示全部组", action: #selector(menuShowAll), keyEquivalent: "")
        showAll.target = self
        menu.addItem(showAll)
        let hideAll = NSMenuItem(title: "隐藏全部组", action: #selector(menuHideAll), keyEquivalent: "")
        hideAll.target = self
        menu.addItem(hideAll)
        menu.addItem(NSMenuItem.separator())

        let settings = NSMenuItem(title: "设置…（⌘,）", action: #selector(menuOpenSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "退出 \(Config.appName)", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    /// 根据快捷键表，生成绑定在指定键上的功能菜单项
    private func hotkeyItem(keyCode: UInt32, keyDisplay: String) -> NSMenuItem? {
        guard let cfg = manager.settings.hotkeys.first(where: {
            $0.binding?.keyCode == keyCode && $0.binding?.modifiers == Config.HotKey.switchModifiers
        }) else { return nil }
        let title = "\(functionTitle(cfg.function))（\(keyDisplay)）"
        let item = NSMenuItem(title: title, action: #selector(runFunctionTag(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = cfg.function.tag
        return item
    }

    private func functionTitle(_ function: HotkeyFunction) -> String {
        switch function {
        case .specificGroup(let id):
            let name = manager.settings.groups.first { $0.id == id }?.name ?? "组"
            return "切换至「\(name)」"
        default:
            return function.display
        }
    }

    // MARK: - 菜单动作（target = self）

    @objc private func runFunctionTag(_ sender: NSMenuItem) {
        guard let tag = sender.representedObject as? String,
              let function = HotkeyFunction.fromTag(tag) else { return }
        manager.perform(function)
    }
    @objc private func menuOpenGroup(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID {
            manager.showGroup(id: id)
        }
    }
    @objc private func menuShowAll() { manager.showAll() }
    @objc private func menuHideAll() { manager.hideAll() }
    @objc private func menuOpenSettings() { openSettings() }
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
