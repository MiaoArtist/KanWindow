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

    // MARK: - 动作分发

    func perform(_ action: GlobalSwitchAction) {
        switch action {
        case .next: cycleSite(1)
        case .previous: cycleSite(-1)
        case .specificGroup(let id):
            if let c = controllers[id] {
                showController(c)
            }
        case .none: break
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

    // MARK: - 热键编排

    func applyHotkeys() {
        var specs: [GlobalHotKey.Spec] = []

        specs.append(GlobalHotKey.Spec(id: 1,
                                       keyCode: Config.HotKey.toggleKeyCode,
                                       modifiers: Config.HotKey.toggleModifiers) { [weak self] in
            self?.toggle()
        })

        // ⌥⌘D / ⌥⌘E = 当前组内上/下切网址（或按设置做“切到指定组/无”）
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

        // 每个启用组的专属呼出快捷键
        for (i, g) in settings.groups.enumerated() {
            guard g.enabled, let h = g.hotKey else { continue }
            let groupID = g.id
            specs.append(GlobalHotKey.Spec(id: UInt32(1000 + i),
                                           keyCode: h.keyCode,
                                           modifiers: h.modifiers) { [weak self] in
                self?.showGroup(id: groupID)
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
