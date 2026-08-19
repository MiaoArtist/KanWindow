import Foundation

/// 配置持久化：存 UserDefaults（JSON），支持导出/导入，并做多版本迁移。
final class SettingsStore {

    static let storageKey = "AppSettings"

    /// 读取配置。自动做两类迁移：
    /// ① 数据格式：v0.2(浮窗) / v0.3(组+D/E动作) → v0.4(组+统一快捷键表)
    /// ② bundle id：旧版 `dev.miaoartist.aifloatwindow` 域 → 新版 `dev.miaoartist.kanwindow` 域（改名后不丢设置）
    static func load() -> AppSettings {
        let defaults = UserDefaults.standard

        // 1) 新 bundle id 域
        if let data = defaults.data(forKey: storageKey),
           let s = decodeOrMigrate(data), !s.groups.isEmpty {
            return s
        }

        // 2) 旧 bundle id 域（改名迁移）
        if let old = UserDefaults(suiteName: Config.oldBundleIdentifier),
           let data = old.data(forKey: storageKey),
           let s = decodeOrMigrate(data), !s.groups.isEmpty {
            save(s)     // 写入新域
            return s
        }

        // 全新安装
        return defaultsInstall()
    }

    private static func decodeOrMigrate(_ data: Data) -> AppSettings? {
        // 当前版
        if let s = try? JSONDecoder().decode(AppSettings.self, from: data), !s.groups.isEmpty {
            return s
        }
        // v0.3 分组版
        if let legacy = try? JSONDecoder().decode(LegacyV3Settings.self, from: data),
           !legacy.groups.isEmpty {
            return legacy.migrated()
        }
        // v0.2 浮窗版
        if let legacy = try? JSONDecoder().decode(LegacyV2Settings.self, from: data),
           !legacy.panes.isEmpty {
            return legacy.migrated()
        }
        return nil
    }

    private static func defaultsInstall() -> AppSettings {
        var fresh = AppSettings.defaults()
        let defaults = UserDefaults.standard
        if let url = defaults.string(forKey: "DoubaoURL") ?? UserDefaults(suiteName: Config.oldBundleIdentifier)?.string(forKey: "DoubaoURL"),
           fresh.groups.first?.sites.count ?? 0 > 0 {
            fresh.groups[0].sites[0].url = url
        }
        save(fresh)
        return fresh
    }

    static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    // MARK: - 导入 / 导出

    static func export(_ settings: AppSettings, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: url)
    }

    static func importData(from url: URL) throws -> AppSettings {
        let data = try Data(contentsOf: url)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        guard !settings.groups.isEmpty else {
            throw SettingsStoreError.emptyGroups
        }
        return settings
    }

    enum SettingsStoreError: LocalizedError {
        case emptyGroups
        var errorDescription: String? {
            "导入的配置里没有网址组（groups 为空），已取消导入。"
        }
    }
}

// MARK: - 迁移

/// 旧的 ⌥⌘D/E 动作（与 v0.2/v0.3 的 GlobalSwitchAction 同构）
private enum LegacyAction: Codable, Equatable {
    case next, previous, specific(UUID), none

    private enum Kind: String, Codable { case next, previous, specific, none }
    private enum CodingKeys: String, CodingKey { case kind, id }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .next: self = .next
        case .previous: self = .previous
        case .none: self = .none
        case .specific:
            if let id = try? c.decode(UUID.self, forKey: .id) { self = .specific(id) }
            else { self = .none }
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .next: try c.encode(Kind.next, forKey: .kind)
        case .previous: try c.encode(Kind.previous, forKey: .kind)
        case .none: try c.encode(Kind.none, forKey: .kind)
        case .specific(let id):
            try c.encode(Kind.specific, forKey: .kind)
            try c.encode(id, forKey: .id)
        }
    }

    var function: HotkeyFunction? {
        switch self {
        case .next: return .nextSite
        case .previous: return .previousSite
        case .specific(let id): return .specificGroup(id)
        case .none: return nil
        }
    }
}

/// v0.3 的分组结构
private struct LegacyV3Settings: Codable {
    struct G: Codable {
        var id: UUID
        var name: String
        var sites: [SiteConfig]
        var hotKey: HotKeyBinding?
        var enabled: Bool
        var idleMinutes: Int?
        var frame: FrameSnapshot?
        var activeSiteIndex: Int

        enum CodingKeys: String, CodingKey {
            case id, name, sites, hotKey, enabled, idleMinutes, frame, activeSiteIndex
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? "组"
            sites = try c.decodeIfPresent([SiteConfig].self, forKey: .sites) ?? []
            hotKey = try c.decodeIfPresent(HotKeyBinding.self, forKey: .hotKey)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            idleMinutes = try c.decodeIfPresent(Int.self, forKey: .idleMinutes)
            frame = try c.decodeIfPresent(FrameSnapshot.self, forKey: .frame)
            activeSiteIndex = try c.decodeIfPresent(Int.self, forKey: .activeSiteIndex) ?? 0
        }
    }
    var groups: [G]
    var globalIdleMinutes: Int
    var dAction: LegacyAction
    var eAction: LegacyAction

    func migrated() -> AppSettings {
        let newGroups = groups.map { g in
            GroupConfig(
                id: g.id, name: g.name, sites: g.sites,
                enabled: g.enabled, idleMinutes: g.idleMinutes,
                frame: g.frame, activeSiteIndex: g.activeSiteIndex
            )
        }
        var hotkeys: [HotkeyConfig] = []

        // ⌥Space 显示/隐藏当前组（必须有，保证基础可用）
        hotkeys.append(HotkeyConfig(
            function: .toggleCurrent,
            binding: HotKeyBinding(keyCode: Config.HotKey.toggleKeyCode,
                                   modifiers: Config.HotKey.toggleModifiers)))

        // 旧 dAction/eAction
        if let f = dAction.function {
            hotkeys.append(HotkeyConfig(
                function: f,
                binding: HotKeyBinding(keyCode: Config.HotKey.switchKeyCodeD,
                                       modifiers: Config.HotKey.switchModifiers)))
        }
        if let f = eAction.function {
            hotkeys.append(HotkeyConfig(
                function: f,
                binding: HotKeyBinding(keyCode: Config.HotKey.switchKeyCodeE,
                                       modifiers: Config.HotKey.switchModifiers)))
        }

        // 旧的“组专属快捷键” → 变成“切换至指定组”行
        for g in groups where g.hotKey != nil {
            hotkeys.append(HotkeyConfig(
                function: .specificGroup(g.id),
                binding: g.hotKey))
        }

        return AppSettings(groups: newGroups,
                           globalIdleMinutes: globalIdleMinutes,
                           hotkeys: hotkeys)
    }
}

/// v0.2 的浮窗结构
private struct LegacyV2Settings: Codable {
    struct Pane: Codable {
        var id: UUID
        var name: String
        var url: String
        var hotKey: HotKeyBinding?
        var enabled: Bool
        var idleMinutes: Int?
        var frame: FrameSnapshot?
    }
    var panes: [Pane]
    var globalIdleMinutes: Int
    var dAction: LegacyAction
    var eAction: LegacyAction

    func migrated() -> AppSettings {
        let groups = panes.map { p in
            GroupConfig(id: p.id, name: p.name,
                        sites: [SiteConfig(name: p.name, url: p.url)],
                        enabled: p.enabled, idleMinutes: p.idleMinutes, frame: p.frame)
        }
        return AppSettings(groups: groups,
                           globalIdleMinutes: globalIdleMinutes,
                           hotkeys: AppSettings.defaults().hotkeys)
    }
}
