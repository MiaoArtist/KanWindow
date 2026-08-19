import AppKit

/// 浮窗编排器：管理所有浮窗窗口、全局热键、闲置计时联动。
final class PaneManager {

    private(set) var settings: AppSettings
    private var controllers: [UUID: PaneController] = [:]
    private var order: [UUID] = []                  // 启用的浮窗顺序
    private(set) weak var activeController: PaneController?
    private var localMonitor: Any?

    /// 设置被保存/变更后回调（AppDelegate 用来刷新状态栏菜单）
    var onSettingsChanged: (() -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
        rebuildControllers()
        installLocalMonitor()
        applyHotkeys()
    }

    // MARK: - 公开状态

    /// 启用状态的浮窗（用于状态栏菜单 / 循环）
    var enabledPanes: [PaneConfig] { settings.panes.filter { $0.enabled } }

    func isPaneVisible(_ id: UUID) -> Bool {
        controllers[id]?.isVisible ?? false
    }

    // MARK: - 设置变更

    func update(_ newSettings: AppSettings) {
        settings = newSettings
        SettingsStore.save(newSettings)
        rebuildControllers()
        applyHotkeys()
        onSettingsChanged?()
    }

    /// 应用退 出前把还在显示的窗存下来
    func saveAllFrames() {
        for (id, c) in controllers {
            if let w = c.window {
                applyFrame(FrameSnapshot(from: w.frame), for: id, save: false)
            }
        }
        SettingsStore.save(settings)
    }

    // MARK: - 显示 / 隐藏 / 循环

    /// ⌥Space：显示 / 隐藏“当前浮窗”（没有则显示第一个）
    func toggle() {
        if let act = activeController {
            if act.isVisible {
                act.hide()
            } else {
                showController(act)
            }
        } else if let firstID = order.first, let c = controllers[firstID] {
            showController(c)
        }
    }

    func showPane(id: UUID) {
        guard let c = controllers[id] else { return }
        showController(c)
    }

    func hideAll() {
        for c in controllers.values where c.isVisible {
            c.hide()
        }
        activeController = nil
    }

    func showAll() {
        for (i, id) in order.enumerated() {
            guard let c = controllers[id] else { continue }
            if c.window == nil {
                // 首次创建：居中 + 轻微错位，避免完全重叠
                c.show(rememberedFrame: nil)
                if let w = c.window {
                    w.setFrameOrigin(NSPoint(x: w.frame.origin.x + CGFloat(i % 5) * 28,
                                             y: w.frame.origin.y - CGFloat(i % 5) * 28))
                }
            } else {
                c.show(rememberedFrame: settings.panes.first { $0.id == id }?.frame)
            }
        }
        if let firstID = order.first {
            activeController = controllers[firstID]
        }
    }

    // MARK: - 内部

    private func showController(_ c: PaneController) {
        // “同时只显示一个”语义：先收起其它
        for (_, other) in controllers where other.id != c.id && other.isVisible {
            other.hide()
        }
        let remembered = settings.panes.first { $0.id == c.id }?.frame
        c.show(rememberedFrame: remembered)
        activeController = c
    }

    private func cycle(_ direction: Int) {
        guard !order.isEmpty else { return }
        var startIdx = order.count - 1
        if let act = activeController, let i = order.firstIndex(of: act.id) {
            startIdx = i
        }
        let target = (startIdx + direction + order.count) % order.count
        if let c = controllers[order[target]] {
            showController(c)
        }
    }

    func perform(_ action: GlobalSwitchAction) {
        switch action {
        case .next: cycle(1)
        case .previous: cycle(-1)
        case .specific(let id):
            if let c = controllers[id] {
                showController(c)
            }
        case .none: break
        }
    }

    // MARK: - 控制器重建（增删/启停/改名/改址）

    private func rebuildControllers() {
        let enabled = settings.panes.filter { $0.enabled }
        let enabledIDs = Set(enabled.map { $0.id })
        var newControllers: [UUID: PaneController] = [:]

        for p in enabled {
            if let existing = controllers[p.id] {
                existing.update(p, globalIdle: settings.globalIdleMinutes)
                newControllers[p.id] = existing
            } else {
                let c = PaneController(config: p, globalIdle: settings.globalIdleMinutes) { [weak self] id, snap in
                    self?.applyFrame(snap, for: id)
                }
                newControllers[p.id] = c
            }
        }

        // 被禁用 / 被删除的浮窗：释放
        for (id, c) in controllers where !enabledIDs.contains(id) {
            c.dispose()
        }
        controllers = newControllers
        order = enabled.map { $0.id }

        if let act = activeController, !enabledIDs.contains(act.id) {
            activeController = nil
        }
    }

    private func applyFrame(_ snap: FrameSnapshot, for id: UUID, save: Bool = true) {
        if let idx = settings.panes.firstIndex(where: { $0.id == id }) {
            settings.panes[idx].frame = snap
            if save {
                SettingsStore.save(settings)
            }
        }
    }

    // MARK: - 热键编排

    func applyHotkeys() {
        var specs: [GlobalHotKey.Spec] = []

        // ⌥Space = 切换当前浮窗
        specs.append(GlobalHotKey.Spec(id: 1,
                                       keyCode: Config.HotKey.toggleKeyCode,
                                       modifiers: Config.HotKey.toggleModifiers) { [weak self] in
            self?.toggle()
        })

        // ⌥⌘D / ⌥⌘E = 设置里的动作
        specs.append(GlobalHotKey.Spec(id: 2,
                                       keyCode: Config.HotKey.switchKeyCodeD,
                                       modifiers: Config.HotKey.switchModifiers) { [weak self] in
            self?.perform(self?.settings.dAction ?? .none)
        })
        specs.append(GlobalHotKey.Spec(id: 3,
                                       keyCode: Config.HotKey.switchKeyCodeE,
                                       modifiers: Config.HotKey.switchModifiers) { [weak self] in
            self?.perform(self?.settings.eAction ?? .none)
        })

        // 每个启用浮窗的自定义快捷键（默认无）
        for (i, p) in settings.panes.enumerated() {
            guard p.enabled, let h = p.hotKey else { continue }
            let paneID = p.id
            specs.append(GlobalHotKey.Spec(id: UInt32(1000 + i),
                                           keyCode: h.keyCode,
                                           modifiers: h.modifiers) { [weak self] in
                self?.showPane(id: paneID)
            })
        }

        GlobalHotKey.apply(specs)
    }

    // MARK: - 窗口内交互 → 重置各自闲置计时

    private func installLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]
        ) { [weak self] event in
            guard let self = self else { return event }
            let winNum = event.windowNumber
            if winNum > 0, let win = NSApp.window(withWindowNumber: winNum),
               let c = self.controllers.values.first(where: { $0.window === win }) {
                c.noteInteraction()
            }
            return event
        }
    }
}
