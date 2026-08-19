import AppKit
import UniformTypeIdentifiers

/// 设置面板（分组版）：网址组管理、组内站点管理、全局 D/E 动作、导入导出。
final class SettingsWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {

    let window: NSWindow
    private let manager: GroupManager
    private var draft: AppSettings

    // 组表格 / 站点表格（用 tag 区分）
    private let groupsTable = NSTableView()
    private let sitesTable = NSTableView()

    // 组编辑器
    private let groupNameField = NSTextField()
    private let groupIdleField = NSTextField()
    private let groupEnableCheckbox = NSButton(checkboxWithTitle: "启用此组", target: nil, action: nil)
    private let groupHotkeyButton = NSButton(title: "", target: nil, action: nil)
    private let groupHotkeyClear = NSButton(title: "清除", target: nil, action: nil)

    // 站点编辑器
    private let siteNameField = NSTextField()
    private let siteUrlField = NSTextField()

    // 全局
    private let globalIdleField = NSTextField()
    private let dActionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let eActionPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    private var dActions: [GlobalSwitchAction] = []
    private var eActions: [GlobalSwitchAction] = []
    private var recordingMonitor: Any?

    init(manager: GroupManager) {
        self.manager = manager
        self.draft = manager.settings
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
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
        self.groupsTable.tag = 0
        self.sitesTable.tag = 1
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

    // MARK: - UI 构建

    private func buildUI() {
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = content

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        let contentWidth: CGFloat = 720 - 18 * 2   // 684

        root.addArrangedSubview(sectionTitle("网址组"))

        // —— 组：左列表 + 右编辑 ——
        let groupsRow = NSStackView()
        groupsRow.orientation = .horizontal
        groupsRow.alignment = .top
        groupsRow.spacing = 14
        root.addArrangedSubview(groupsRow)

        let groupsScroll = makeScrollTable(groupsTable, columns: makeCheckColumn("开") + [makeColumn("组名", 200)])
        groupsScroll.widthAnchor.constraint(equalToConstant: 250).isActive = true
        groupsScroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        groupsRow.addArrangedSubview(groupsScroll)

        groupNameField.widthAnchor.constraint(equalToConstant: 260).isActive = true
        groupNameField.font = .systemFont(ofSize: 12)
        groupNameField.target = self
        groupNameField.action = #selector(groupEditorChanged(_:))
        groupNameField.placeholderString = "组名，如：AI 助手"

        groupIdleField.widthAnchor.constraint(equalToConstant: 80).isActive = true
        groupIdleField.font = .systemFont(ofSize: 12)
        groupIdleField.target = self
        groupIdleField.action = #selector(groupEditorChanged(_:))
        groupIdleField.placeholderString = "全局"

        groupEnableCheckbox.target = self
        groupEnableCheckbox.action = #selector(groupEditorChanged(_:))

        groupHotkeyButton.title = "未设置"
        groupHotkeyButton.bezelStyle = .rounded
        groupHotkeyButton.widthAnchor.constraint(equalToConstant: 170).isActive = true
        groupHotkeyButton.target = self
        groupHotkeyButton.action = #selector(recordGroupHotkey)

        groupHotkeyClear.bezelStyle = .rounded
        groupHotkeyClear.widthAnchor.constraint(equalToConstant: 62).isActive = true
        groupHotkeyClear.target = self
        groupHotkeyClear.action = #selector(clearGroupHotkey)

        let groupForm = NSGridView(views: [
            [formLabel("组名称"), groupNameField],
            [formLabel("自动隐藏(分钟)"), groupIdleField, formNote("留空=全局；0=不隐藏")],
            [groupEnableCheckbox],
            [formLabel("呼出快捷键"), groupHotkeyButton, groupHotkeyClear],
        ])
        groupForm.rowSpacing = 8
        groupForm.columnSpacing = 12
        groupForm.column(at: 0).width = 130
        groupsRow.addArrangedSubview(groupForm)

        // —— 组：增删按钮 ——
        let groupButtons = NSStackView()
        groupButtons.orientation = .horizontal
        groupButtons.spacing = 8
        root.addArrangedSubview(groupButtons)
        groupButtons.addArrangedSubview(smallButton("＋", action: #selector(addGroup)))
        groupButtons.addArrangedSubview(smallButton("－", action: #selector(removeGroup)))
        groupButtons.addArrangedSubview(formNote("组名在列表里勾选可启用/停用"))

        root.addArrangedSubview(separator())

        // —— 站点 ——
        root.addArrangedSubview(sectionTitle("组内网址（⌥⌘D / ⌥⌘E 在组内切换）"))

        let sitesRow = NSStackView()
        sitesRow.orientation = .horizontal
        sitesRow.alignment = .top
        sitesRow.spacing = 14
        root.addArrangedSubview(sitesRow)

        let sitesScroll = makeScrollTable(sitesTable, columns: [makeColumn("名称", 100), makeColumn("网址", 130)])
        sitesScroll.widthAnchor.constraint(equalToConstant: 250).isActive = true
        sitesScroll.heightAnchor.constraint(equalToConstant: 140).isActive = true
        sitesRow.addArrangedSubview(sitesScroll)

        siteNameField.widthAnchor.constraint(equalToConstant: 260).isActive = true
        siteNameField.font = .systemFont(ofSize: 12)
        siteNameField.target = self
        siteNameField.action = #selector(siteEditorChanged(_:))
        siteNameField.placeholderString = "如：豆包"

        siteUrlField.widthAnchor.constraint(equalToConstant: 260).isActive = true
        siteUrlField.font = .systemFont(ofSize: 12)
        siteUrlField.target = self
        siteUrlField.action = #selector(siteEditorChanged(_:))
        siteUrlField.placeholderString = "https://…"

        let siteForm = NSGridView(views: [
            [formLabel("站点名称"), siteNameField],
            [formLabel("网址"), siteUrlField],
        ])
        siteForm.rowSpacing = 8
        siteForm.columnSpacing = 12
        siteForm.column(at: 0).width = 130
        sitesRow.addArrangedSubview(siteForm)

        let siteButtons = NSStackView()
        siteButtons.orientation = .horizontal
        siteButtons.spacing = 8
        root.addArrangedSubview(siteButtons)
        siteButtons.addArrangedSubview(smallButton("＋", action: #selector(addSite)))
        siteButtons.addArrangedSubview(smallButton("－", action: #selector(removeSite)))

        root.addArrangedSubview(separator())

        // —— 全局 ——
        root.addArrangedSubview(sectionTitle("全局"))

        globalIdleField.widthAnchor.constraint(equalToConstant: 80).isActive = true
        globalIdleField.font = .systemFont(ofSize: 12)
        globalIdleField.target = self
        globalIdleField.action = #selector(globalChanged(_:))
        globalIdleField.placeholderString = "15"

        dActionPopup.widthAnchor.constraint(equalToConstant: 260).isActive = true
        dActionPopup.target = self
        dActionPopup.action = #selector(dActionChanged(_:))
        eActionPopup.widthAnchor.constraint(equalToConstant: 260).isActive = true
        eActionPopup.target = self
        eActionPopup.action = #selector(eActionChanged(_:))

        let globalForm = NSGridView(views: [
            [formLabel("自动隐藏(分钟)"), globalIdleField, formNote("全局默认；组可单独覆盖")],
            [formLabel("⌥⌘D 动作"), dActionPopup],
            [formLabel("⌥⌘E 动作"), eActionPopup],
        ])
        globalForm.rowSpacing = 8
        globalForm.columnSpacing = 12
        globalForm.column(at: 0).width = 130
        root.addArrangedSubview(globalForm)

        // —— 底部按钮 ——
        let buttonsRow = NSStackView()
        buttonsRow.orientation = .horizontal
        buttonsRow.alignment = .centerY
        buttonsRow.spacing = 10
        buttonsRow.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        root.addArrangedSubview(buttonsRow)

        buttonsRow.addArrangedSubview(standardButton("恢复默认", action: #selector(restoreClicked)))
        buttonsRow.addArrangedSubview(standardButton("导入…", action: #selector(importClicked)))
        buttonsRow.addArrangedSubview(standardButton("导出…", action: #selector(exportClicked)))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttonsRow.addArrangedSubview(spacer)

        buttonsRow.addArrangedSubview(standardButton("取消", action: #selector(cancelClicked)))
        buttonsRow.addArrangedSubview(standardButton("保存", action: #selector(saveClicked)))

        root.addArrangedSubview(formNote("提示：左键点顶部栏图标 = 呼出/收起弹窗；右键 = 菜单(设置)。在窗口里按 ⌘, 也能打开设置。"))
    }

    // MARK: - UI 小工具

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 14)
        return label
    }

    private func formLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        return label
    }

    private func formNote(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 320).isActive = true
        return box
    }

    private func smallButton(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.widthAnchor.constraint(equalToConstant: 34).isActive = true
        return b
    }

    private func standardButton(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        return b
    }

    private func makeColumn(_ title: String, _ width: CGFloat) -> NSTableColumn {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(title))
        col.title = title
        col.width = width
        return col
    }

    private func makeCheckColumn(_ title: String) -> [NSTableColumn] {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("enabled"))
        col.title = title
        col.width = 34
        return [col]
    }

    private func makeScrollTable(_ table: NSTableView, columns: [NSTableColumn]) -> NSScrollView {
        table.delegate = self
        table.dataSource = self
        table.rowHeight = 24
        table.allowsEmptySelection = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        for col in columns {
            table.addTableColumn(col)
        }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table
        return scroll
    }

    // MARK: - 数据刷新

    private func reloadAll() {
        groupsTable.reloadData()
        sitesTable.reloadData()
        globalIdleField.stringValue = String(draft.globalIdleMinutes)
        rebuildActionPopups()
        if groupsTable.numberOfRows > 0 {
            groupsTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        reloadGroupEditor()
        reloadSiteEditor()
    }

    private func rebuildActionPopups() {
        rebuildPopup(dActionPopup, into: &dActions, current: draft.dAction)
        rebuildPopup(eActionPopup, into: &eActions, current: draft.eAction)
    }

    private func rebuildPopup(_ popup: NSPopUpButton, into actions: inout [GlobalSwitchAction], current: GlobalSwitchAction) {
        popup.removeAllItems()
        var list: [GlobalSwitchAction] = [.next, .previous]
        popup.addItem(withTitle: "组内下一个网址")
        popup.addItem(withTitle: "组内上一个网址")
        for g in draft.groups where g.enabled {
            list.append(.specificGroup(g.id))
            popup.addItem(withTitle: "切到「\(g.name)」")
        }
        list.append(.none)
        popup.addItem(withTitle: "无动作")
        actions = list

        if let idx = list.firstIndex(where: { $0 == current }) {
            popup.selectItem(at: idx)
        } else if let noneIdx = list.firstIndex(where: { $0 == .none }) {
            popup.selectItem(at: noneIdx)
        }
    }

    // MARK: - 选中与编辑器

    private func selectedGroupIndex() -> Int? {
        let row = groupsTable.selectedRow
        guard row >= 0, row < draft.groups.count else { return nil }
        return row
    }

    private func selectedSiteIndex() -> Int? {
        let row = sitesTable.selectedRow
        guard let gi = selectedGroupIndex(),
              gi < draft.groups.count,
              row >= 0, row < draft.groups[gi].sites.count else { return nil }
        return row
    }

    private func reloadGroupEditor() {
        guard let gi = selectedGroupIndex() else {
            groupNameField.stringValue = ""
            groupIdleField.stringValue = ""
            groupEnableCheckbox.state = .off
            groupHotkeyButton.title = "未设置"
            groupNameField.isEnabled = false
            groupIdleField.isEnabled = false
            groupEnableCheckbox.isEnabled = false
            groupHotkeyButton.isEnabled = false
            groupHotkeyClear.isEnabled = false
            return
        }
        let g = draft.groups[gi]
        groupNameField.isEnabled = true
        groupIdleField.isEnabled = true
        groupEnableCheckbox.isEnabled = true
        groupHotkeyButton.isEnabled = true
        groupHotkeyClear.isEnabled = true
        groupNameField.stringValue = g.name
        groupIdleField.stringValue = g.idleMinutes.map(String.init) ?? ""
        groupEnableCheckbox.state = g.enabled ? .on : .off
        groupHotkeyButton.title = g.hotKey?.display ?? "未设置（点击录制）"
        reloadSiteEditor()
    }

    private func reloadSiteEditor() {
        let gi = selectedGroupIndex()
        guard let si = selectedSiteIndex() else {
            siteNameField.stringValue = ""
            siteUrlField.stringValue = ""
            siteNameField.isEnabled = gi != nil
            siteUrlField.isEnabled = gi != nil
            return
        }
        guard let gi = gi else { return }
        let s = draft.groups[gi].sites[si]
        siteNameField.isEnabled = true
        siteUrlField.isEnabled = true
        siteNameField.stringValue = s.name
        siteUrlField.stringValue = s.url
    }

    // MARK: - 提交（保存时统一回写）

    private func commitAllEditors() {
        commitGroupEditor()
        commitSiteEditor()
    }

    private func commitGroupEditor() {
        guard let gi = selectedGroupIndex() else { return }
        draft.groups[gi].name = groupNameField.stringValue.isEmpty ? "未命名" : groupNameField.stringValue
        draft.groups[gi].enabled = groupEnableCheckbox.state == .on
        let t = groupIdleField.stringValue.trimmingCharacters(in: .whitespaces)
        draft.groups[gi].idleMinutes = t.isEmpty ? nil : Int(t)
    }

    private func commitSiteEditor() {
        guard let gi = selectedGroupIndex(), let si = selectedSiteIndex() else { return }
        draft.groups[gi].sites[si].name = siteNameField.stringValue.isEmpty ? "未命名" : siteNameField.stringValue
        draft.groups[gi].sites[si].url = siteUrlField.stringValue
    }

    // MARK: - 表格

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === groupsTable { return draft.groups.count }
        if let gi = selectedGroupIndex(), gi < draft.groups.count {
            return draft.groups[gi].sites.count
        }
        return 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let col = tableColumn else { return nil }
        let cell = NSTableCellView()

        if tableView === groupsTable {
            guard row < draft.groups.count else { return nil }
            let g = draft.groups[row]
            if col.identifier.rawValue == "enabled" {
                let cb = NSButton(checkboxWithTitle: "", target: self, action: #selector(groupEnableToggled(_:)))
                cb.state = g.enabled ? .on : .off
                cb.tag = row
                cell.addSubview(cb)
                pinCenter(cb, in: cell, leading: 4)
            } else {
                cell.addSubview(textCell(g.name))
                pinText(textCellHolder: cell)
            }
        } else {
            guard let gi = selectedGroupIndex(), gi < draft.groups.count,
                  row < draft.groups[gi].sites.count else { return nil }
            let s = draft.groups[gi].sites[row]
            if col.identifier.rawValue == "名称" {
                cell.addSubview(textCell(s.name))
                pinText(textCellHolder: cell)
            } else {
                cell.addSubview(textCell(s.url))
                pinText(textCellHolder: cell)
            }
        }
        return cell
    }

    private func textCell(_ text: String) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.lineBreakMode = .byTruncatingTail
        tf.font = .systemFont(ofSize: 12)
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }

    private func pinText(textCellHolder cell: NSTableCellView) {
        guard let tf = cell.subviews.first as? NSTextField else { return }
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            tf.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
    }

    private func pinCenter(_ view: NSView, in cell: NSTableCellView, leading: CGFloat) {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: leading),
            view.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView else { return }
        if table === groupsTable {
            reloadGroupEditor()
        } else if table === sitesTable {
            reloadSiteEditor()
        }
    }

    @objc private func groupEnableToggled(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0, row < draft.groups.count else { return }
        draft.groups[row].enabled = sender.state == .on
        groupsTable.reloadData()
        rebuildActionPopups()
        reloadGroupEditor()
    }

    @objc private func groupEditorChanged(_ sender: NSControl) {
        commitGroupEditor()
        if sender === groupNameField || sender === groupEnableCheckbox {
            reloadGroupsRows()
            rebuildActionPopups()
        }
        reloadSiteEditor()
    }

    @objc private func siteEditorChanged(_ sender: NSControl) {
        commitSiteEditor()
        if sender === siteNameField {
            reloadSitesRows()
        }
    }

    private func reloadGroupsRows() {
        let sel = groupsTable.selectedRow
        groupsTable.reloadData()
        if sel >= 0 {
            groupsTable.selectRowIndexes(IndexSet(integer: sel), byExtendingSelection: false)
        }
    }

    private func reloadSitesRows() {
        let sel = sitesTable.selectedRow
        sitesTable.reloadData()
        if sel >= 0 {
            sitesTable.selectRowIndexes(IndexSet(integer: sel), byExtendingSelection: false)
        }
    }

    // MARK: - 增删

    @objc private func addGroup() {
        commitAllEditors()
        var name = "新组"
        var n = 2
        while draft.groups.contains(where: { $0.name == name }) {
            name = "新组 \(n)"
            n += 1
        }
        draft.groups.append(GroupConfig(name: name, sites: [SiteConfig(name: "新网址", url: "https://")]))
        groupsTable.reloadData()
        rebuildActionPopups()
        groupsTable.selectRowIndexes(IndexSet(integer: draft.groups.count - 1), byExtendingSelection: false)
        reloadGroupEditor()
    }

    @objc private func removeGroup() {
        guard draft.groups.count > 1 else {
            presentAlert(text: "至少要保留一个网址组。")
            return
        }
        commitAllEditors()
        guard let gi = selectedGroupIndex() else { return }
        draft.groups.remove(at: gi)
        groupsTable.reloadData()
        sitesTable.reloadData()
        rebuildActionPopups()
        reloadGroupEditor()
    }

    @objc private func addSite() {
        guard let gi = selectedGroupIndex() else {
            presentAlert(text: "请先选中一个网址组。")
            return
        }
        commitSiteEditor()
        var name = "新网址"
        var n = 2
        while draft.groups[gi].sites.contains(where: { $0.name == name }) {
            name = "新网址 \(n)"
            n += 1
        }
        draft.groups[gi].sites.append(SiteConfig(name: name, url: "https://"))
        sitesTable.reloadData()
        sitesTable.selectRowIndexes(IndexSet(integer: draft.groups[gi].sites.count - 1), byExtendingSelection: false)
        reloadSiteEditor()
    }

    @objc private func removeSite() {
        commitAllEditors()
        guard let gi = selectedGroupIndex(), draft.groups[gi].sites.count > 1 else {
            presentAlert(text: "每个组至少要保留一个网址。")
            return
        }
        guard let si = selectedSiteIndex() else { return }
        draft.groups[gi].sites.remove(at: si)
        sitesTable.reloadData()
        reloadSiteEditor()
    }

    // MARK: - 快捷键录制（组呼出快捷键）

    @objc private func recordGroupHotkey() {
        commitGroupEditor()
        guard let gi = selectedGroupIndex() else {
            presentAlert(text: "请先在列表里选中一个网址组。")
            return
        }
        _ = gi
        guard recordingMonitor == nil else { return }
        groupHotkeyButton.title = "按下新快捷键…（Esc 取消）"
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let code = event.keyCode
            if Self.modifierKeyCodes.contains(code) { return event }
            if code == 53 {
                self.stopRecording()
                self.reloadGroupEditor()
                return event
            }
            var mods: UInt32 = 0
            let f = event.modifierFlags
            if f.contains(.command) { mods |= GlobalHotKey.Mods.command }
            if f.contains(.option)  { mods |= GlobalHotKey.Mods.option }
            if f.contains(.shift)   { mods |= GlobalHotKey.Mods.shift }
            if f.contains(.control) { mods |= GlobalHotKey.Mods.control }
            self.commitGroupHotkey(HotKeyBinding(keyCode: UInt32(code), modifiers: mods))
            self.stopRecording()
            self.reloadGroupEditor()
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

    private func commitGroupHotkey(_ binding: HotKeyBinding) {
        guard let gi = selectedGroupIndex() else { return }
        draft.groups[gi].hotKey = binding
    }

    @objc private func clearGroupHotkey() {
        guard let gi = selectedGroupIndex() else { return }
        draft.groups[gi].hotKey = nil
        reloadGroupEditor()
    }

    // MARK: - 全局动作

    @objc private func globalChanged(_ sender: NSControl) {
        let t = globalIdleField.stringValue.trimmingCharacters(in: .whitespaces)
        if let v = Int(t), v >= 0 {
            draft.globalIdleMinutes = v
        }
    }

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

    // MARK: - 导入导出 / 恢复默认

    @objc private func exportClicked() {
        commitAllEditors()
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
                draft = try SettingsStore.importData(from: url)
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
        commitAllEditors()

        let t = globalIdleField.stringValue.trimmingCharacters(in: .whitespaces)
        if let v = Int(t), v >= 0 {
            draft.globalIdleMinutes = v
        } else {
            draft.globalIdleMinutes = 15
        }

        // 空网址清理 + 校验
        for i in draft.groups.indices {
            draft.groups[i].sites.removeAll { $0.url.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        draft.groups.removeAll { $0.sites.isEmpty }
        if draft.groups.isEmpty {
            presentAlert(text: "至少需要一个包含网址的组。")
            return
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

        for g in settings.groups where g.enabled {
            if let h = g.hotKey {
                add(h, "组「\(g.name)」")
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
