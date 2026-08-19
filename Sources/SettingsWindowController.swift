import AppKit
import UniformTypeIdentifiers

/// 设置面板：管理浮窗列表、每浮窗网址/启用/闲置/自定义快捷键、全局 D/E 动作、导入导出。
final class SettingsWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {

    let window: NSWindow
    private let manager: PaneManager
    private var draft: AppSettings

    // UI
    private let tableView = NSTableView()
    private let nameField = NSTextField()
    private let urlField = NSTextField()
    private let enableCheckbox = NSButton(checkboxWithTitle: "启用该浮窗（停用不建窗口、不吃内存）",
                                          target: nil, action: nil)
    private let idleField = NSTextField()
    private let recorderButton = NSButton(title: "", target: nil, action: nil)
    private let clearKeyButton = NSButton(title: "清除", target: nil, action: nil)
    private let globalIdleField = NSTextField()
    private let dActionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let eActionPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    private var dActions: [GlobalSwitchAction] = []
    private var eActions: [GlobalSwitchAction] = []
    private var recordingMonitor: Any?

    init(manager: PaneManager) {
        self.manager = manager
        self.draft = manager.settings
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "\(Config.appName) · 设置"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.delegate = self
        buildUI()
        reloadAll()
    }

    func show() {
        draft = manager.settings
        reloadAll()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - 布局

    private func buildUI() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 580, height: 640))
        window.contentView = content

        add(label: "悬浮窗", bold: true, x: 20, y: 600, content)

        // 表格
        let enabledCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("enabled"))
        enabledCol.title = "开"
        enabledCol.width = 34
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "名称"
        nameCol.width = 200
        tableView.addTableColumn(enabledCol)
        tableView.addTableColumn(nameCol)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 24
        tableView.allowsEmptySelection = true
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        let scroll = NSScrollView(frame: NSRect(x: 20, y: 432, width: 250, height: 166))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = tableView
        content.addSubview(scroll)

        let addButton = button("＋", action: #selector(addClicked), frame: NSRect(x: 20, y: 400, width: 60, height: 24))
        content.addSubview(addButton)
        let removeButton = button("－", action: #selector(removeClicked), frame: NSRect(x: 86, y: 400, width: 60, height: 24))
        content.addSubview(removeButton)
        add(label: "增/删浮窗", small: true, x: 152, y: 405, content)

        // 编辑器
        add(label: "名称", small: true, x: 300, y: 574, content)
        textField(nameField, frame: NSRect(x: 300, y: 548, width: 256, height: 24), placeholder: "如：豆包")
        content.addSubview(nameField)

        add(label: "网址（可自定义）", small: true, x: 300, y: 514, content)
        textField(urlField, frame: NSRect(x: 300, y: 488, width: 256, height: 24), placeholder: "https://…")
        content.addSubview(urlField)

        enableCheckbox.frame = NSRect(x: 300, y: 452, width: 256, height: 22)
        enableCheckbox.target = self
        enableCheckbox.action = #selector(editorChanged(_:))
        content.addSubview(enableCheckbox)

        add(label: "自动隐藏（分钟，留空＝跟随全局）", small: true, x: 300, y: 420, content)
        textField(idleField, frame: NSRect(x: 300, y: 394, width: 90, height: 24), placeholder: "全局")
        content.addSubview(idleField)

        add(label: "自定义快捷键（默认无）", small: true, x: 300, y: 362, content)
        recorderButton.title = "未设置"
        recorderButton.bezelStyle = .rounded
        recorderButton.frame = NSRect(x: 300, y: 336, width: 170, height: 26)
        recorderButton.target = self
        recorderButton.action = #selector(recorderClicked)
        content.addSubview(recorderButton)
        clearKeyButton.bezelStyle = .rounded
        clearKeyButton.frame = NSRect(x: 478, y: 336, width: 70, height: 26)
        clearKeyButton.target = self
        clearKeyButton.action = #selector(clearHotkey)
        content.addSubview(clearKeyButton)

        separator(y: 386, content)

        add(label: "全局", bold: true, x: 20, y: 356, content)

        add(label: "自动隐藏（分钟）", small: true, x: 20, y: 326, content)
        textField(globalIdleField, frame: NSRect(x: 150, y: 326, width: 70, height: 24), placeholder: "15")
        content.addSubview(globalIdleField)

        add(label: "⌥⌘D 动作", small: true, x: 20, y: 294, content)
        configurePopup(dActionPopup, frame: NSRect(x: 110, y: 294, width: 230, height: 24), action: #selector(dActionChanged(_:)))
        content.addSubview(dActionPopup)

        add(label: "⌥⌘E 动作", small: true, x: 20, y: 262, content)
        configurePopup(eActionPopup, frame: NSRect(x: 110, y: 262, width: 230, height: 24), action: #selector(eActionChanged(_:)))
        content.addSubview(eActionPopup)

        // 底部按钮
        let exportB = button("导出…", action: #selector(exportClicked), frame: NSRect(x: 20, y: 20, width: 70, height: 26))
        content.addSubview(exportB)
        let importB = button("导入…", action: #selector(importClicked), frame: NSRect(x: 96, y: 20, width: 70, height: 26))
        content.addSubview(importB)
        let resetB = button("恢复默认", action: #selector(restoreClicked), frame: NSRect(x: 172, y: 20, width: 88, height: 26))
        content.addSubview(resetB)
        let cancelB = button("取消", action: #selector(cancelClicked), frame: NSRect(x: 420, y: 20, width: 62, height: 26))
        content.addSubview(cancelB)
        let saveB = button("保存", action: #selector(saveClicked), frame: NSRect(x: 488, y: 20, width: 62, height: 26))
        content.addSubview(saveB)
    }



    // MARK: - UI 小工具

    private func add(label text: String,
                     bold: Bool = false,
                     small: Bool = false,
                     x: CGFloat,
                     y: CGFloat,
                     _ container: NSView) {
        let label = NSTextField(labelWithString: text)
        label.font = bold
            ? .boldSystemFont(ofSize: 15)
            : (small ? .systemFont(ofSize: 11) : .systemFont(ofSize: 12))
        label.textColor = bold ? .labelColor : .secondaryLabelColor
        label.frame = NSRect(x: x, y: y, width: 320, height: 18)
        container.addSubview(label)
    }

    private func textField(_ field: NSTextField, frame: NSRect, placeholder: String) {
        field.frame = frame
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 12)
        field.target = self
        field.action = #selector(editorChanged(_:))
    }

    private func button(_ title: String, action: Selector, frame: NSRect) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.frame = frame
        return b
    }

    private func configurePopup(_ popup: NSPopUpButton, frame: NSRect, action: Selector) {
        popup.frame = frame
        popup.target = self
        popup.action = action
    }

    private func separator(y: CGFloat, _ container: NSView) {
        let box = NSBox(frame: NSRect(x: 20, y: y, width: 540, height: 1))
        box.boxType = .separator
        container.addSubview(box)
    }

    // MARK: - 数据刷新

    private func reloadAll() {
        tableView.reloadData()
        globalIdleField.stringValue = String(draft.globalIdleMinutes)
        rebuildActionPopups()
        if tableView.numberOfRows > 0 {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        reloadEditor()
    }

    private func rebuildActionPopups() {
        rebuildPopup(dActionPopup, into: &dActions, current: draft.dAction)
        rebuildPopup(eActionPopup, into: &eActions, current: draft.eAction)
    }

    private func rebuildPopup(_ popup: NSPopUpButton, into actions: inout [GlobalSwitchAction], current: GlobalSwitchAction) {
        popup.removeAllItems()
        var list: [GlobalSwitchAction] = [.next, .previous]
        popup.addItem(withTitle: "下一个浮窗")
        popup.addItem(withTitle: "上一个浮窗")
        for p in draft.panes where p.enabled {
            list.append(.specific(p.id))
            popup.addItem(withTitle: "切到「\(p.name)」")
        }
        list.append(.none)
        popup.addItem(withTitle: "无动作")
        actions = list

        if let idx = list.firstIndex(where: { $0 == current }) {
            popup.selectItem(at: idx)
        } else {
            // 之前指定到的浮窗被禁用/删除 → 落到“无动作”
            if let noneIdx = list.firstIndex(where: { $0 == .none }) {
                popup.selectItem(at: noneIdx)
            }
        }
    }

    private func reloadEditor() {
        guard let id = selectedPaneID(),
              let idx = draft.panes.firstIndex(where: { $0.id == id }) else {
            nameField.stringValue = ""
            urlField.stringValue = ""
            enableCheckbox.state = .off
            idleField.stringValue = ""
            recorderButton.title = "未设置"
            return
        }
        let p = draft.panes[idx]
        nameField.stringValue = p.name
        urlField.stringValue = p.url
        enableCheckbox.state = p.enabled ? .on : .off
        idleField.stringValue = p.idleMinutes.map(String.init) ?? ""
        recorderButton.title = p.hotKey?.display ?? "未设置（点击录制）"
    }

    private func selectedPaneID() -> UUID? {
        let row = tableView.selectedRow
        guard row >= 0, row < draft.panes.count else { return nil }
        return draft.panes[row].id
    }

    /// 把编辑器里的当前值写回选中的浮窗
    private func commitEditorToDraft() {
        guard let id = selectedPaneID(),
              let idx = draft.panes.firstIndex(where: { $0.id == id }) else { return }
        draft.panes[idx].name = nameField.stringValue.isEmpty ? "未命名" : nameField.stringValue
        draft.panes[idx].url = urlField.stringValue
        draft.panes[idx].enabled = enableCheckbox.state == .on
        let t = idleField.stringValue.trimmingCharacters(in: .whitespaces)
        draft.panes[idx].idleMinutes = t.isEmpty ? nil : Int(t)
    }

    // MARK: - 表格

    func numberOfRows(in tableView: NSTableView) -> Int {
        draft.panes.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let col = tableColumn, row < draft.panes.count else { return nil }
        let pane = draft.panes[row]
        let cell = NSTableCellView()

        if col.identifier.rawValue == "enabled" {
            let cb = NSButton(checkboxWithTitle: "", target: self, action: #selector(tableEnableToggled(_:)))
            cb.state = pane.enabled ? .on : .off
            cb.tag = row
            cb.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(cb)
            NSLayoutConstraint.activate([
                cb.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                cb.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        } else {
            let tf = NSTextField(labelWithString: pane.name)
            tf.lineBreakMode = .byTruncatingTail
            tf.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(tf)
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                tf.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // 只加载，不提交：选中的改变不该把旧输入写进草稿
        reloadEditor()
    }

    @objc private func tableEnableToggled(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0, row < draft.panes.count else { return }
        draft.panes[row].enabled = sender.state == .on
        tableView.reloadData()
        rebuildActionPopups()
        reloadEditor()
    }

    @objc private func editorChanged(_ sender: NSControl) {
        commitEditorToDraft()
        if sender === enableCheckbox || sender === nameField {
            reloadRowPreservingSelection()
            rebuildActionPopups()   // 名称会出现在 D/E 动作下拉里
        }
    }

    private func reloadRowPreservingSelection() {
        let sel = tableView.selectedRow
        tableView.reloadData()
        if sel >= 0 {
            tableView.selectRowIndexes(IndexSet(integer: sel), byExtendingSelection: false)
        }
    }

    // MARK: - 增删

    @objc private func addClicked() {
        commitEditorToDraft()
        var name = "新浮窗"
        var n = 2
        while draft.panes.contains(where: { $0.name == name }) {
            name = "新浮窗 \(n)"
            n += 1
        }
        draft.panes.append(PaneConfig(name: name, url: "https://"))
        tableView.reloadData()
        rebuildActionPopups()
        tableView.selectRowIndexes(IndexSet(integer: draft.panes.count - 1), byExtendingSelection: false)
        reloadEditor()
    }

    @objc private func removeClicked() {
        guard draft.panes.count > 1 else {
            presentAlert(text: "至少要保留一个浮窗。")
            return
        }
        commitEditorToDraft()
        guard let id = selectedPaneID() else { return }
        draft.panes.removeAll { $0.id == id }
        tableView.reloadData()
        rebuildActionPopups()
        reloadEditor()
    }

    // MARK: - D/E 动作

    @objc private func dActionChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        if idx >= 0, idx < dActions.count {
            draft.dAction = dActions[idx]
        }
    }

    @objc private func eActionChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        if idx >= 0, idx < eActions.count {
            draft.eAction = eActions[idx]
        }
    }

    // MARK: - 热键录制

    @objc private func recorderClicked() {
        commitEditorToDraft()
        guard selectedPaneID() != nil else {
            presentAlert(text: "请先在列表里选中一个浮窗。")
            return
        }
        guard recordingMonitor == nil else { return }
        recorderButton.title = "按下新快捷键…（Esc 取消）"
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let code = event.keyCode
            if Self.modifierKeyCodes.contains(code) {
                return event
            }
            if code == 53 {  // Esc 取消
                self.stopRecording()
                self.reloadEditor()
                return event
            }
            var mods: UInt32 = 0
            let f = event.modifierFlags
            if f.contains(.command) { mods |= GlobalHotKey.Mods.command }
            if f.contains(.option)  { mods |= GlobalHotKey.Mods.option }
            if f.contains(.shift)   { mods |= GlobalHotKey.Mods.shift }
            if f.contains(.control) { mods |= GlobalHotKey.Mods.control }
            self.commitHotkey(HotKeyBinding(keyCode: UInt32(code), modifiers: mods))
            self.stopRecording()
            self.reloadEditor()
            return event
        }
    }

    private static let modifierKeyCodes: Set<UInt16> = [55, 56, 57, 58, 59, 60, 61, 62, 63, 64]

    private func stopRecording() {
        if let m = recordingMonitor {
            NSEvent.removeMonitor(m)
            recordingMonitor = nil
        }
    }

    @objc private func clearHotkey() {
        guard let id = selectedPaneID(),
              let idx = draft.panes.firstIndex(where: { $0.id == id }) else { return }
        draft.panes[idx].hotKey = nil
        reloadEditor()
    }

    private func commitHotkey(_ binding: HotKeyBinding) {
        guard let id = selectedPaneID(),
              let idx = draft.panes.firstIndex(where: { $0.id == id }) else { return }
        draft.panes[idx].hotKey = binding
    }

    // MARK: - 导入导出 / 恢复默认

    @objc private func exportClicked() {
        commitEditorToDraft()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "悬浮窗配置.json"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try SettingsStore.export(draft, to: url)
            } catch {
                presentAlert(text: "导出失败：\(error.localizedDescription)")
            }
        }
    }

    @objc private func importClicked() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let imported = try SettingsStore.importData(from: url)
                draft = imported
                reloadAll()
            } catch {
                presentAlert(text: error.localizedDescription)
            }
        }
    }

    @objc private func restoreClicked() {
        draft = AppSettings.defaults()
        reloadAll()
    }

    // MARK: - 保存 / 取消

    @objc private func saveClicked() {
        commitEditorToDraft()

        // 全局闲置时间
        let t = globalIdleField.stringValue.trimmingCharacters(in: .whitespaces)
        if let v = Int(t), v >= 0 {
            draft.globalIdleMinutes = v
        } else {
            draft.globalIdleMinutes = 15
        }

        if let conflict = hotkeyConflict(in: draft) {
            presentAlert(text: conflict)
            return
        }

        manager.update(draft)
        window.orderOut(nil)
    }

    @objc private func cancelClicked() {
        window.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        stopRecording()
        window.orderOut(nil)
        return false
    }

    // MARK: - 校验

    /// 检查是否有多处用了同一组快捷键；返回冲突描述（nil=无冲突）
    private func hotkeyConflict(in settings: AppSettings) -> String? {
        var map: [String: String] = [:]
        var conflict: String?

        func add(_ binding: HotKeyBinding, _ label: String) {
            let key = "\(binding.keyCode)|\(binding.modifiers)"
            if let owner = map[key] {
                conflict = "快捷键 \(binding.display) 同时被「\(owner)」和「\(label)」使用，会产生冲突。\n请换一个或清除其中一个。"
            } else {
                map[key] = label
            }
        }

        add(HotKeyBinding(keyCode: Config.HotKey.toggleKeyCode, modifiers: Config.HotKey.toggleModifiers), "显示/隐藏（⌥Space）")
        add(HotKeyBinding(keyCode: Config.HotKey.switchKeyCodeD, modifiers: Config.HotKey.switchModifiers), "⌥⌘D 动作")
        add(HotKeyBinding(keyCode: Config.HotKey.switchKeyCodeE, modifiers: Config.HotKey.switchModifiers), "⌥⌘E 动作")

        for p in settings.panes where p.enabled {
            if let h = p.hotKey {
                add(h, "浮窗「\(p.name)」")
            }
        }
        return conflict
    }

    // MARK: - 弹窗

    private func presentAlert(text: String) {
        let a = NSAlert()
        a.messageText = text
        a.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        a.beginSheetModal(for: window)
    }
}
