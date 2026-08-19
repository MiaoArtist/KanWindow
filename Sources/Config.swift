import Foundation

/// 全局常量与固定默认值
enum Config {
    static let bundleIdentifier = "dev.miaoartist.kanwindow"      // 新 bundle id（配置随它走，见 SettingsStore 迁移）
    static let oldBundleIdentifier = "dev.miaoartist.aifloatwindow"  // 旧版 bundle id（用于迁移配置）

    static let appName = "窥窗"
    static let appNameEnglish = "KanWindow"

    /// 新浮窗的默认尺寸（首次打开；之后记住用户调整过的尺寸）
    static let defaultWindowSize = NSSize(width: 420, height: 660)

    /// 自定义 UA：WKWebView 默认 UA 会被部分站点（如 B 站）判定“浏览器版本过低”。
    /// 这里伪装成较新的 Safari，让多数现代 Web 功能被放行。
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    /// 全局快捷键（键可在这里改）
    /// 键码：Space=49、D=2、E=14（ANSI 布局，字母不是顺序号）
    enum HotKey {
        static let toggleKeyCode: UInt32 = 49            // Space
        static let switchKeyCodeD: UInt32 = 2            // D
        static let switchKeyCodeE: UInt32 = 14           // E
        static let toggleModifiers: UInt32 = GlobalHotKey.Mods.option
        static let switchModifiers: UInt32 = GlobalHotKey.Mods.option | GlobalHotKey.Mods.command
    }
}
