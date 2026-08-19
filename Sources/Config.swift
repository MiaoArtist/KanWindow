import Foundation

/// 全局配置：站点 URL、窗口尺寸、空闲自动隐藏时间。
///
/// 支持两种方式修改：
/// 1. 直接改本文件里的常量（源码方式）；
/// 2. 不改代码，在终端用 `defaults write` 覆盖（推荐，见 README「配置」一节）。
struct Config {
    static let bundleIdentifier = "dev.miaoartist.aifloatwindow"
    static let appName = "在线 AI 悬浮窗"
    static let defaultSiteName = "豆包"

    // MARK: - 站点（可用 defaults 覆盖）
    static var doubaoURL: String {
        string("DoubaoURL", default: "https://www.doubao.com/")
    }
    static var deepseekURL: String {
        string("DeepseekURL", default: "https://chat.deepseek.com/")
    }

    // MARK: - 窗口（可用 defaults 覆盖）
    static var windowWidth: CGFloat {
        CGFloat(double("WindowWidth", default: 420))
    }
    static var windowHeight: CGFloat {
        CGFloat(double("WindowHeight", default: 660))
    }

    // MARK: - 空闲自动隐藏（分钟，可用 defaults 覆盖）
    static var idleMinutes: Int {
        int("IdleMinutes", default: 15)
    }

    // MARK: - 全局快捷键（改这里即可换键）
    // 键码说明：Space=49, D=2, E=14（可在 macOS「键盘设置」里用系统建测试/用 Copilot 查）
    enum HotKey {
        static var toggleKeyCode: UInt32 { 49 }   // Space
        static var doubaoKeyCode: UInt32 { 2 }    // D
        static var deepseekKeyCode: UInt32 { 14 } // E
        static var toggleModifiers: UInt32 { GlobalHotKey.Mods.option }
        static var switchModifiers: UInt32 { GlobalHotKey.Mods.option | GlobalHotKey.Mods.command }
    }

    // MARK: - defaults 读取工具
    private static func string(_ key: String, default value: String) -> String {
        UserDefaults.standard.object(forKey: key) as? String ?? value
    }
    private static func double(_ key: String, default value: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double
            ?? (UserDefaults.standard.object(forKey: key) as? NSNumber)?.doubleValue
            ?? value
    }
    private static func int(_ key: String, default value: Int) -> Int {
        UserDefaults.standard.object(forKey: key) as? Int
            ?? (UserDefaults.standard.object(forKey: key) as? NSNumber)?.intValue
            ?? value
    }
}
