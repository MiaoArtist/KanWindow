import Foundation

/// 配置的持久化：存 UserDefaults（JSON），支持导出/导入 JSON 文件
final class SettingsStore {

    static let storageKey = "AppSettings"

    /// 读取配置；首次运行生成默认配置（并吸收旧版 single-window 的 URL 设置）
    static func load() -> AppSettings {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: storageKey),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data),
           !settings.panes.isEmpty {
            return settings
        }

        // 首次运行：迁移旧版（单一窗口版）手动配置过的 URL
        var fresh = AppSettings.defaults()
        if !fresh.panes.isEmpty {
            if fresh.panes.count > 0, let url = defaults.string(forKey: "DoubaoURL") {
                fresh.panes[0].url = url
            }
            if fresh.panes.count > 1, let url = defaults.string(forKey: "DeepseekURL") {
                fresh.panes[1].url = url
            }
        }
        save(fresh)
        return fresh
    }

    static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    // MARK: - 导入/导出

    static func export(_ settings: AppSettings, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: url)
    }

    static func importData(from url: URL) throws -> AppSettings {
        let data = try Data(contentsOf: url)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        guard !settings.panes.isEmpty else {
            throw SettingsStoreError.emptyPanes
        }
        return settings
    }

    enum SettingsStoreError: LocalizedError {
        case emptyPanes
        var errorDescription: String? {
            "导入的配置里没有浮窗（panes 为空），已取消导入。"
        }
    }
}
