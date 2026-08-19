import Foundation

/// 配置持久化：存 UserDefaults（JSON），支持导出/导入 JSON 文件
final class SettingsStore {

    static let storageKey = "AppSettings"

    /// 读取配置；首次运行生成默认；自动迁移 v0.2 的「浮窗(panes)」结构 → 分组(groups)
    static func load() -> AppSettings {
        let defaults = UserDefaults.standard

        // 1) 新版结构
        if let data = defaults.data(forKey: storageKey),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data),
           !settings.groups.isEmpty {
            return settings
        }

        // 2) 旧版（v0.2 单组多浮窗）结构 → 迁移
        if let data = defaults.data(forKey: storageKey),
           let legacy = try? JSONDecoder().decode(LegacyAppSettings.self, from: data),
           !legacy.panes.isEmpty {
            let migrated = legacy.migrated()
            save(migrated)
            return migrated
        }

        // 3) 全新安装（并吸收更早 single-window 版改过的 URL）
        var fresh = AppSettings.defaults()
        if let url = defaults.string(forKey: "DoubaoURL"), fresh.groups.first?.sites.count ?? 0 > 0 {
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

// MARK: - v0.2 旧结构迁移

/// v0.2 的「浮窗」结构（每个浮窗 = 一个组内网址）
private struct LegacyAppSettings: Codable {
    struct LegacyPane: Codable {
        var id: UUID
        var name: String
        var url: String
        var hotKey: HotKeyBinding?
        var enabled: Bool
        var idleMinutes: Int?
        var frame: FrameSnapshot?
    }
    var panes: [LegacyPane]
    var globalIdleMinutes: Int
    var dAction: GlobalSwitchAction
    var eAction: GlobalSwitchAction

    func migrated() -> AppSettings {
        let groups = panes.map { pane in
            GroupConfig(
                id: pane.id,
                name: pane.name,
                sites: [SiteConfig(name: pane.name, url: pane.url)],
                hotKey: pane.hotKey,
                enabled: pane.enabled,
                idleMinutes: pane.idleMinutes,
                frame: pane.frame,
                activeSiteIndex: 0
            )
        }
        return AppSettings(groups: groups,
                           globalIdleMinutes: globalIdleMinutes,
                           dAction: dAction,
                           eAction: eAction)
    }
}
