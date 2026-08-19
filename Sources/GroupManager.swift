import AppKit

/// 组编排器：管理所有网址组的悬浮窗、全局热键、组内切站。
final class GroupManager {

    private(set) var settings: AppSettings
    private var controllers: [UUID: GroupController] = [:]
    private var order: [UUID] = []                 // 启用的组顺序
    private(set) weak var activeController: GroupController?
    private var localMonitor: Any?

    var onSettingsChanged: (() -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
        rebuildControllers()
        installLocalMonitor()
        applyHotkeys()
    }

    // MARK: - 公开状态

    var enabledGroups: [GroupConfig] { settings.groups.filter { $0.enabled } }

    func isGroupVisible(_ id: UUID) -> Bool {
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

    func saveAllFrames() {
        for (id, c) in controllers {
            if let w = c.window {
                applyFrame(FrameSnapshot(from: w.frame), for: id, save: false)
            }
        }
        SettingsStore.save(settings)
    }

    // MARK: - 显示 / 隐藏 / 切站

    /// ⌥Space：显示 / 隐藏当前组（没有则显示第一个组）
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

    /// 呼出指定组（隐藏其它组）
    func showGroup(id: UUID) {
        guard let c = controllers[id] else { return }
        showController(c)
    }

    /// ⌥⌘D / ⌥⌘E：在当前组内切换网址
    func cycleSite(_ direction: Int) {
        guard let act = activeController else {
            // 还没激活组：先呼出第一个组
            if let firstID = order.first, let c = controllers[firstID] {
                showController(c)
            }
            return
        }
        act.switchSite(by: direction)
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
                c.show(rememberedFrame: nil)
                if let w = c.window {
                    w.setFrameOrigin(NSPoint(x: w.frame.origin.x + CGFloat(i % 5) * 28,
                                             y: w.frame.origin.y - CGFloat(i % 5) * 28))
                }
            } else {
                c.show(rememberedFrame: settings.groups.first { $0.id == id }?.frame)
            }
        }
        if let firstID = order.first {
            activeController = controllers[firstID]
        }
    }

    // MARK: - 动作分发（由统一快捷键表驱动）

    func perform(_ function: HotkeyFunction) {
        switch function {
        case .toggleCurrent:
            toggle()
        case .nextSite:
            cycleSite(1)
        case .previousSite:
            cycleSite(-1)
        case .nextGroup:
            cycleGroup(1)
        case .previousGroup:
            cycleGroup(-1)
        case .specificGroup(let id):
            if let c = controllers[id] {
                showController(c)
            }
        case .refresh:
            refreshCurrentGroup()
        }
    }

    /// 切换上/下一个“组”（使目标组成为当前组并呼出）
    private func cycleGroup(_ direction: Int) {
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

    /// 刷新当前组浮窗页面
    private func refreshCurrentGroup() {
        if let act = activeController {
            act.reloadCurrentSite()
        }
    }

    // MARK: - 内部

    private func showController(_ c: GroupController) {
        for (_, other) in controllers where other.id != c.id && other.isVisible {
            other.hide()
        }
        let remembered = settings.groups.first { $0.id == c.id }?.frame
        c.show(rememberedFrame: remembered)
        activeController = c
    }

    private func rebuildControllers() {
        let enabled = settings.groups.filter { $0.enabled }
        let enabledIDs = Set(enabled.map { $0.id })
        var newControllers: [UUID: GroupController] = [:]

        for g in enabled {
            if let existing = controllers[g.id] {
                existing.update(g, globalIdle: settings.globalIdleMinutes)
                newControllers[g.id] = existing
            } else {
                let c = GroupController(
                    config: g,
                    globalIdle: settings.globalIdleMinutes,
                    onFrameChanged: { [weak self] id, snap in
                        self?.applyFrame(snap, for: id)
                    },
                    onActiveSiteChanged: { [weak self] id, index in
                        self?.applyActiveSiteIndex(index, for: id)
                    }
                )
                newControllers[g.id] = c
            }
        }

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
        if let idx = settings.groups.firstIndex(where: { $0.id == id }) {
            settings.groups[idx].frame = snap
            if save {
                SettingsStore.save(settings)
            }
        }
    }

    private func applyActiveSiteIndex(_ index: Int, for id: UUID) {
        if let idx = settings.groups.firstIndex(where: { $0.id == id }) {
            settings.groups[idx].activeSiteIndex = index
            SettingsStore.save(settings)
        }
    }

    // MARK: - 热键编排（全部来自“统一快捷键表”）

    func applyHotkeys() {
        var specs: [GlobalHotKey.Spec] = []
        for (i, cfg) in settings.hotkeys.enumerated() {
            guard let b = cfg.binding else { continue }
            let function = cfg.function
            specs.append(GlobalHotKey.Spec(id: UInt32(100 + i),
                                           keyCode: b.keyCode,
                                           modifiers: b.modifiers) { [weak self] in
                self?.perform(function)
            })
        }
        GlobalHotKey.apply(specs)
    }

    // MARK: - 窗口内交互 → 重置组闲置计时

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
