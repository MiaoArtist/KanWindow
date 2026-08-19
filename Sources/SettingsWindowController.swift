import AppKit
import UniformTypeIdentifiers

/// 设置面板（v0.4）：网址组 / 组内网址 / 全局快捷键 三块 + 底部自动关闭与按钮。
final class SettingsWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {

    let window: NSWindow
    private let manager: GroupManager
    private var draft: AppSettings

    // 表格
    private let groupsTable = NSTableView()
    private let sitesTable = NSTableView()
    private let hotkeysTable = NSTableView()

    // 组编辑器
    private let groupNameField = NSTextField()
    private let groupIdleField = NSTextField()
    private let groupEnableCheckbox = NSButton(checkboxWithTitle: "启用此组", target: nil, action: nil)

    // 站点编辑器
    private let siteNameField = NSTextField()
    private let siteUrlField = NSTextField()

    // 快捷键编辑器
    private let hotkeyFunctionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let hotkeyRecordButton = NSButton(title: "未设置", target: nil, action: nil)
    private let hotkeyClearButton = NSButton(title: "清除", target: nil, action: nil)

    // 底部
    private let globalIdleField = NSTextField()

    // 站点区灰化所需引用
    private var sitesTitleLabel: NSTextField!
    private var sitesScroll: NSScrollView!
    private var addSiteButton: NSButton!
    private var removeSiteButton: NSButton!
    private var siteFormViews: [NSView] = []

    // 快捷键功能区选项映射（popup 行号 → 功能）
    private var functionOptions: [(HotkeyFunction, String)] = []

    private var recordingMonitor: Any?

    init(manager: GroupManager) {
        self.manager = manager
        self.draft = manager.settings
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 720),
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
        groupsTable.tag = 0
        sitesTable.tag = 1
        hotkeysTable.tag = 2
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
        root.edgeInsets = NSEdgeInsets(top: 14, left: 30, bottom: 14, right: 30)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        let contentWidth: CGFloat = 800 - 60   // 30 + 30 内边距 = 740

        // ===== ① 网址组 =====
        root.addArrangedSubview(sectionTitle("网址组"))
        let groupsRow = NSStackView()
        groupsRow.orientation = .horizontal
        groupsRow.spacing = 16
        groupsRow.alignment = .top
        groupsRow.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        root.addArrangedSubview(groupsRow)

        let groupsScroll = makeScrollTable(groupsTable, columns: [checkColumn("启用"), textColumn("组名", 250)])
        groupsScroll.widthAnchor.constraint(equalToConstant: 360).isActive = true
        groupsScroll.heightAnchor.constraint(equalToConstant: 132).isActive = true
        groupsRow.addArrangedSubview(groupsScroll)

        groupNameField.widthAnchor.constraint(equalToConstant: 190).isActive = true
        groupNameField.font = .systemFont(ofSize: 12)
        groupNameField.target = self
        groupNameField.action = #selector(groupEditorChanged(_:))
        groupNameField.placeholderString = "组名，如：AI 助手"

        groupIdleField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        groupIdleField.font = .systemFont(ofSize: 12)
        groupIdleField.target = self
        groupIdleField.action = #selector(groupEditorChanged(_:))
        groupIdleField.placeholderString = "全局"

        groupEnableCheckbox.target = self
        groupEnableCheckbox.action = #selector(groupEditorChanged(_:))

        let groupForm = NSGridView(views: [
            [formLabel("组名称"), groupNameField],
            [groupEnableCheckbox],
            [formLabel("自动关闭(分)"), groupIdleField, formNote("留空=全局")],
        ])
        groupForm.rowSpacing = 7
        groupForm.columnSpacing = 10
        groupForm.column(at: 0).width = 92
        groupsRow.addArrangedSubview(groupForm)

        let groupButtons = NSStackView()
        groupButtons.orientation = .horizontal
        groupButtons.spacing = 8
        root.addArrangedSubview(groupButtons)
        groupButtons.addArrangedSubview(smallButton("＋", action: #selector(addGroup)))
        groupButtons.addArrangedSubview(smallButton("－", action: #selector(removeGroup)))
        groupButtons.addArrangedSubview(formNote("列表里勾选可启用/停用（停用不建窗口、不吃内存）"))

        // ===== ② 组内网址（未选中组时整体置灰） =====
        sitesTitleLabel = sectionTitle("组内网址")
        root.addArrangedSubview(sitesTitleLabel)

        let sitesRow = NSStackView()
        sitesRow.orientation = .horizontal
        sitesRow.spacing = 16
        sitesRow.alignment = .top
        sitesRow.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        root.addArrangedSubview(sitesRow)

        sitesScroll = makeScrollTable(sitesTable, columns: [textColumn("名称", 110), textColumn("网址", 230)])
        sitesScroll.widthAnchor.constraint(equalToConstant: 360).isActive = true
        sitesScroll.heightAnchor.constraint(equalToConstant: 132).isActive = true
        sitesRow.addArrangedSubview(sitesScroll)

        siteNameField.widthAnchor.constraint(equalToConstant: 190).isActive = true
        siteNameField.font = .systemFont(ofSize: 12)
        siteNameField.target = self
        siteNameField.action = #selector(siteEditorChanged(_:))
        siteNameField.placeholderString = "如：豆包"

        siteUrlField.widthAnchor.constraint(equalToConstant: 190).isActive = true
        siteUrlField.font = .systemFont(ofSize: 12)
        siteUrlField.target = self
        siteUrlField.action = #selector(siteEditorChanged(_:))
        siteUrlField.placeholderString = "https://…"

        let siteForm = NSGridView(views: [
            [formLabel("站点名称"), siteNameField],
            [formLabel("网址"), siteUrlField],
        ])
        siteForm.rowSpacing = 7
        siteForm.columnSpacing = 10
        siteForm.column(at: 0).width = 72
        sitesRow.addArrangedSubview(siteForm)
        siteFormViews = [siteNameField, siteUrlField, siteForm]

        addSiteButton = smallButton("＋", action: #selector(addSite))
        removeSiteButton = smallButton("－", action: #selector(removeSite))
        let siteButtons = NSStackView()
        siteButtons.orientation = .horizontal
        siteButtons.spacing = 8
        root.addArrangedSubview(siteButtons)
        siteButtons.addArrangedSubview(addSiteButton)
        siteButtons.addArrangedSubview(removeSiteButton)
        siteButtons.addArrangedSubview(formNote("组内用「组内下一个/上一个网址」快捷键切换 ⌥⌘D/E"))

        // ===== ③ 全局快捷键 =====
        root.addArrangedSubview(sectionTitle("全局快捷键"))

        let hotkeysRow = NSStackView()
        hotkeysRow.orientation = .horizontal
        hotkeysRow.spacing = 16
        hotkeysRow.alignment = .top
        hotkeysRow.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        root.addArrangedSubview(hotkeysRow)

        let hotkeysScroll = makeScrollTable(hotkeysTable, columns: [textColumn("功能", 230), textColumn("按键", 120)])
        hotkeysScroll.widthAnchor.constraint(equalToConstant: 360).isActive = true
        hotkeysScroll.heightAnchor.constraint(equalToConstant: 132).isActive = true
        hotkeysRow.addArrangedSubview(hotkeysScroll)

        hotkeyFunctionPopup.widthAnchor.constraint(equalToConstant: 200).isActive = true
        hotkeyFunctionPopup.target = self
        hotkeyFunctionPopup.action = #selector(hotkeyFunctionChanged(_:))

        hotkeyRecordButton.bezelStyle = .rounded
        hotkeyRecordButton.widthAnchor.constraint(equalToConstant: 150).isActive = true
        hotkeyRecordButton.target = self
        hotkeyRecordButton.action = #selector(recordHotkeyBinding)

        hotkeyClearButton.bezelStyle = .rounded
        hotkeyClearButton.widthAnchor.constraint(equalToConstant: 60).isActive = true
        hotkeyClearButton.target = self
        hotkeyClearButton.action = #selector(clearHotkeyBinding)

        let hotkeyForm = NSGridView(views: [
            [formLabel("功能"), hotkeyFunctionPopup],
            [formLabel("按键"), hotkeyRecordButton, hotkeyClearButton],
        ])
        hotkeyForm.rowSpacing = 8
        hotkeyForm.columnSpacing = 10
        hotkeyForm.column(at: 0).width = 44
        hotkeysRow.addArrangedSubview(hotkeyForm)

        let hotkeyButtons = NSStackView()
        hotkeyButtons.orientation = .horizontal
        hotkeyButtons.spacing = 8
        root.addArrangedSubview(hotkeyButtons)
        hotkeyButtons.addArrangedSubview(smallButton("＋", action: #selector(addHotkey)))
        hotkeyButtons.addArrangedSubview(smallButton("－", action: #selector(removeHotkey)))
        hotkeyButtons.addArrangedSubview(formNote("点＋添加一条，选中后再选功能/录按键"))

        // ===== 底部：全局自动关闭 + 说明 + 按钮 =====
        root.addArrangedSubview(separator())

        let autoRow = NSStackView()
        autoRow.orientation = .horizontal
        autoRow.spacing = 10
        autoRow.alignment = .centerY
        root.addArrangedSubview(autoRow)

        autoRow.addArrangedSubview(formLabel("全局自动关闭(分钟)"))
        globalIdleField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        globalIdleField.font = .systemFont(ofSize: 12)
        globalIdleField.target = self
        globalIdleField.action = #selector(globalIdleChanged(_:))
        globalIdleField.placeholderString = "15"
        autoRow.addArrangedSubview(globalIdleField)

        let explain = NSTextField(wrappingLabelWithString: "「自动关闭」：闲置满 N 分钟会彻底关闭该浮窗并释放网页内存（非只隐藏），需要用快捷键再呼出，会回到原位置、原网站；设 0 为不自动关闭。")
        explain.font = .systemFont(ofSize: 11)
        explain.textColor = .secondaryLabelColor
        explain.widthAnchor.constraint(equalToConstant: 500).isActive = true
        autoRow.addArrangedSubview(explain)

        let buttonsRow = NSStackView()
        buttonsRow.orientation = .horizontal
        buttonsRow.spacing = 10
        buttonsRow.alignment = .centerY
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
        box.widthAnchor.constraint(equalToConstant: 740).isActive = true
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

    private func textColumn(_ title: String, _ width: CGFloat) -> NSTableColumn {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c-" + title))
        col.title = title
        col.width = width
        return col
    }

    private func checkColumn(_ title: String) -> NSTableColumn {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("enabled"))
        col.title = title
        col.width = 46
        return col
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
        hotkeysTable.reloadData()
        globalIdleField.stringValue = String(draft.globalIdleMinutes)
        rebuildFunctionPopup()
        if groupsTable.numberOfRows > 0 {
            groupsTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        reloadGroupEditor()
        reloadSiteEditor()
        reloadHotkeyEditor()
        updateSitesEnabled()
    }

    /// 快捷键功能区下拉内容（功能列表）
    private func rebuildFunctionPopup() {
        hotkeyFunctionPopup.removeAllItems()
        functionOptions = []
        func add(_ f: HotkeyFunction, _ title: String) {
            functionOptions.append((f, title))
            hotkeyFunctionPopup.addItem(withTitle: title)
        }
        add(.toggleCurrent, "显示/隐藏当前组")
        add(.nextSite, "组内下一个网址")
        add(.previousSite, "组内上一个网址")
        add(.nextGroup, "切换下一个组")
        add(.previousGroup, "切换上一个组")
        for g in draft.groups where g.enabled {
            add(.specificGroup(g.id), "切换至「\(g.name)」")
        }
        add(.refresh, "刷新当前浮窗")
        hotkeyFunctionPopup.selectItem(at: 0)
    }

    // MARK: - 选中与编辑器

    private func selectedGroupIndex() -> Int? {
        let row = groupsTable.selectedRow
        guard row >= 0, row < draft.groups.count else { return nil }
        return row
    }

    private func selectedSiteIndex() -> Int? {
        let row = sitesTable.selectedRow
        guard let gi = selectedGroupIndex(), row >= 0, row < draft.groups[gi].sites.count else { return nil }
        return row
    }

    private func selectedHotkeyIndex() -> Int? {
        let row = hotkeysTable.selectedRow
        guard row >= 0, row < draft.hotkeys.count else { return nil }
        return row
    }

    private func reloadGroupEditor() {
        guard let gi = selectedGroupIndex() else {
            groupNameField.stringValue = ""
            groupIdleField.stringValue = ""
            groupEnableCheckbox.state = .off
            setControl(groupNameField, enabled: false)
            setControl(groupIdleField, enabled: false)
            setControl(groupEnableCheckbox, enabled: false)
            reloadSiteEditor()
            return
        }
        let g = draft.groups[gi]
        setControl(groupNameField, enabled: true)
        setControl(groupIdleField, enabled: true)
        setControl(groupEnableCheckbox, enabled: true)
        groupNameField.stringValue = g.name
        groupIdleField.stringValue = g.idleMinutes.map(String.init) ?? ""
        groupEnableCheckbox.state = g.enabled ? .on : .off
        reloadSiteEditor()
    }

    private func reloadSiteEditor() {
        guard let si = selectedSiteIndex(), let gi = selectedGroupIndex() else {
            siteNameField.stringValue = ""
            siteUrlField.stringValue = ""
            setControl(siteNameField, enabled: selectedGroupIndex() != nil)
            setControl(siteUrlField, enabled: selectedGroupIndex() != nil)
            updateSitesEnabled()
            return
        }
        setControl(siteNameField, enabled: true)
        setControl(siteUrlField, enabled: true)
        let s = draft.groups[gi].sites[si]
        siteNameField.stringValue = s.name
        siteUrlField.stringValue = s.url
        updateSitesEnabled()
    }

    private func reloadHotkeyEditor() {
        guard let hi = selectedHotkeyIndex() else {
            hotkeyFunctionPopup.isEnabled = false
            hotkeyRecordButton.isEnabled = false
            hotkeyClearButton.isEnabled = false
            hotkeyRecordButton.title = "未设置"
            return
        }
        hotkeyFunctionPopup.isEnabled = true
        hotkeyRecordButton.isEnabled = true
        hotkeyClearButton.isEnabled = true
        let cfg = draft.hotkeys[hi]
        if let idx = functionOptions.firstIndex(where: { $0.0 == cfg.function }) {
            hotkeyFunctionPopup.selectItem(at: idx)
        } else {
            hotkeyFunctionPopup.selectItem(at: 0)
        }
        hotkeyRecordButton.title = cfg.binding?.display ?? "未设置（点击录制）"
    }

    /// 组内网址区整体置灰（未选中组时）
    private func updateSitesEnabled() {
        let on = selectedGroupIndex() != nil
        sitesTable.isEnabled = on
        sitesScroll.alphaValue = on ? 1.0 : 0.45
        sitesTitleLabel.textColor = on ? .labelColor : .tertiaryLabelColor
        addSiteButton.isEnabled = on
        removeSiteButton.isEnabled = on
        for v in siteFormViews {
            setControl(v, enabled: on)
        }
    }

    private func setControl(_ v: NSView, enabled: Bool) {
        if let ctrl = v as? NSControl {
            ctrl.isEnabled = enabled
        }
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

    private func commitHotkeyEditor() {
        guard let hi = selectedHotkeyIndex() else { return }
        let sel = hotkeyFunctionPopup.indexOfSelectedItem
        if sel >= 0, sel < functionOptions.count {
            draft.hotkeys[hi].function = functionOptions[sel].0
        }
    }

    // MARK: - 表格

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === groupsTable { return draft.groups.count }
        if tableView === hotkeysTable { return draft.hotkeys.count }
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
                pinCenter(cb, in: cell, leading: 6)
            } else {
                addText(g.name, to: cell)
            }
        } else if tableView === hotkeysTable {
            guard row < draft.hotkeys.count else { return nil }
            let cfg = draft.hotkeys[row]
            if col.identifier.rawValue.hasPrefix("c-功能") {
                addText(functionTitle(cfg.function), to: cell)
            } else {
                addText(cfg.binding?.display ?? "（未设置）", to: cell)
            }
        } else { // sites
            guard let gi = selectedGroupIndex(), gi < draft.groups.count,
                  row < draft.groups[gi].sites.count else { return nil }
            let s = draft.groups[gi].sites[row]
            if col.identifier.rawValue.hasPrefix("c-名称") {
                addText(s.name, to: cell)
            } else {
                addText(s.url, to: cell)
            }
        }
        return cell
    }

    private func functionTitle(_ f: HotkeyFunction) -> String {
        switch f {
        case .specificGroup(let id):
            let name = draft.groups.first { $0.id == id }?.name ?? "组"
            return "切换至「\(name)」"
        default:
            return f.display
        }
    }

    private func addText(_ text: String, to cell: NSTableCellView) {
        let tf = NSTextField(labelWithString: text)
        tf.lineBreakMode = .byTruncatingTail
        tf.font = .systemFont(ofSize: 12)
        tf.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(tf)
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 3),
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
            sitesTable.reloadData()      // ← 修 bug：切组后立即刷新站点表
            reloadGroupEditor()
            updateSitesEnabled()
        } else if table === sitesTable {
            reloadSiteEditor()
        } else if table === hotkeysTable {
            reloadHotkeyEditor()
        }
    }

    @objc private func groupEnableToggled(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0, row < draft.groups.count else { return }
        draft.groups[row].enabled = sender.state == .on
        groupsTable.reloadData()
        rebuildFunctionPopup()
        reloadGroupEditor()
    }

    @objc private func groupEditorChanged(_ sender: NSControl) {
        commitGroupEditor()
        if sender === groupNameField || sender === groupEnableCheckbox {
            reloadGroupsRows()
            rebuildFunctionPopup()
        }
        reloadSiteEditor()
    }

    @objc private func siteEditorChanged(_ sender: NSControl) {
        commitSiteEditor()
        if sender === siteNameField {
            let sel = sitesTable.selectedRow
            sitesTable.reloadData()
            if sel >= 0 {
                sitesTable.selectRowIndexes(IndexSet(integer: sel), byExtendingSelection: false)
            }
        }
    }

    @objc private func hotkeyFunctionChanged(_ sender: NSPopUpButton) {
        commitHotkeyEditor()
        let sel = hotkeysTable.selectedRow
        hotkeysTable.reloadData()
        if sel >= 0 {
            hotkeysTable.selectRowIndexes(IndexSet(integer: sel), byExtendingSelection: false)
        }
    }

    private func reloadGroupsRows() {
        let sel = groupsTable.selectedRow
        groupsTable.reloadData()
        if sel >= 0 {
            groupsTable.selectRowIndexes(IndexSet(integer: sel), byExtendingSelection: false)
        }
    }

    // MARK: - 增删（组 / 站点 / 快捷键）

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
        rebuildFunctionPopup()
        groupsTable.selectRowIndexes(IndexSet(integer: draft.groups.count - 1), byExtendingSelection: false)
        reloadGroupEditor()
        updateSitesEnabled()
    }

    @objc private func removeGroup() {
        guard draft.groups.count > 1 else {
            presentAlert(text: "至少要保留一个网址组。")
            return
        }
        commitAllEditors()
        guard let gi = selectedGroupIndex() else { return }
        let removedID = draft.groups[gi].id
        draft.groups.remove(at: gi)
        // 把“切到被删组”的快捷键清掉
        draft.hotkeys.removeAll { f -> Bool in
            if case .specificGroup(let id) = f.function { return id == removedID }
            return false
        }
        groupsTable.reloadData()
        sitesTable.reloadData()
        hotkeysTable.reloadData()
        rebuildFunctionPopup()
        reloadGroupEditor()
        updateSitesEnabled()
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
        guard let gi = selectedGroupIndex() else { return }
        guard draft.groups[gi].sites.count > 1 else {
            presentAlert(text: "每个组至少要保留一个网址。")
            return
        }
        commitSiteEditor()
        guard let si = selectedSiteIndex() else { return }
        draft.groups[gi].sites.remove(at: si)
        sitesTable.reloadData()
        reloadSiteEditor()
    }

    @objc private func addHotkey() {
        commitHotkeyEditor()
        draft.hotkeys.append(HotkeyConfig(function: .nextSite))
        hotkeysTable.reloadData()
        rebuildFunctionPopup()
        hotkeysTable.selectRowIndexes(IndexSet(integer: draft.hotkeys.count - 1), byExtendingSelection: false)
        reloadHotkeyEditor()
    }

    @objc private func removeHotkey() {
        commitHotkeyEditor()
        guard let hi = selectedHotkeyIndex() else { return }
        draft.hotkeys.remove(at: hi)
        hotkeysTable.reloadData()
        rebuildFunctionPopup()
        reloadHotkeyEditor()
    }

    // MARK: - 快捷键录制

    @objc private func recordHotkeyBinding() {
        commitHotkeyEditor()
        guard selectedHotkeyIndex() != nil else {
            presentAlert(text: "请先选中一条快捷键。")
            return
        }
        guard recordingMonitor == nil else { return }
        hotkeyRecordButton.title = "按下新按键…（Esc 取消）"
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let code = event.keyCode
            if Self.modifierKeyCodes.contains(code) { return event }
            if code == 53 {
                self.stopRecording()
                self.reloadHotkeyEditor()
                return event
            }
            var mods: UInt32 = 0
            let f = event.modifierFlags
            if f.contains(.command) { mods |= GlobalHotKey.Mods.command }
            if f.contains(.option)  { mods |= GlobalHotKey.Mods.option }
            if f.contains(.shift)   { mods |= GlobalHotKey.Mods.shift }
            if f.contains(.control) { mods |= GlobalHotKey.Mods.control }
            self.commitHotkeyBinding(HotKeyBinding(keyCode: UInt32(code), modifiers: mods))
            self.stopRecording()
            let sel = self.hotkeysTable.selectedRow
            self.hotkeysTable.reloadData()
            if sel >= 0 {
                self.hotkeysTable.selectRowIndexes(IndexSet(integer: sel), byExtendingSelection: false)
            }
            self.reloadHotkeyEditor()
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

    private func commitHotkeyBinding(_ binding: HotKeyBinding) {
        guard let hi = selectedHotkeyIndex() else { return }
        draft.hotkeys[hi].binding = binding
    }

    @objc private func clearHotkeyBinding() {
        guard let hi = selectedHotkeyIndex() else { return }
        draft.hotkeys[hi].binding = nil
        reloadHotkeyEditor()
    }

    @objc private func globalIdleChanged(_ sender: NSControl) {
        let t = globalIdleField.stringValue.trimmingCharacters(in: .whitespaces)
        if let v = Int(t), v >= 0 {
            draft.globalIdleMinutes = v
        }
    }

    // MARK: - 导入导出 / 恢复默认

    @objc private func exportClicked() {
        commitAllEditors()
        commitHotkeyEditor()
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
        commitHotkeyEditor()

        let t = globalIdleField.stringValue.trimmingCharacters(in: .whitespaces)
        draft.globalIdleMinutes = (Int(t).flatMap { $0 >= 0 ? $0 : nil }) ?? 15

        // 清理：空网址站点、空组、未录按键的快捷键行
        for i in draft.groups.indices {
            draft.groups[i].sites.removeAll { $0.url.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        draft.groups.removeAll { $0.sites.isEmpty }
        if draft.groups.isEmpty {
            presentAlert(text: "至少需要一个包含网址的组。")
            return
        }
        draft.hotkeys.removeAll { $0.binding == nil }
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
        var map: [String: (String, String)] = [:]
        var conflict: String?
        for cfg in settings.hotkeys {
            guard let b = cfg.binding else { continue }
            let key = "\(b.keyCode)|\(b.modifiers)"
            if let (owner, _) = map[key] {
                conflict = "快捷键 \(b.display) 同时被「\(owner)」和「\(functionTitle(cfg.function))」占用。\n请换一个或清除其中一个。"
                break
            } else {
                map[key] = (functionTitle(cfg.function), b.display)
            }
        }
        return conflict
    }

    private func presentAlert(text: String) {
        let a = NSAlert()
        a.messageText = text
        a.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        a.beginSheetModal(for: window)
    }
}
