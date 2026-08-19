import Foundation

/// 全局常量与固定默认值
enum Config {
    static let bundleIdentifier = "dev.miaoartist.aifloatwindow"
    static let appName = "在线 AI 悬浮窗"

    /// 新浮窗的默认尺寸（首次打开；之后记住用户调整过的尺寸）
    static let defaultWindowSize = NSSize(width: 420, height: 660)

    /// 全局快捷键（键可在这里改）
    /// 键码：Space=49、D=2、E=14
    enum HotKey {
        static let toggleKeyCode: UInt32 = 49            // Space
        static let switchKeyCodeD: UInt32 = 2            // D
        static let switchKeyCodeE: UInt32 = 14           // E
        static let toggleModifiers: UInt32 = GlobalHotKey.Mods.option
        static let switchModifiers: UInt32 = GlobalHotKey.Mods.option | GlobalHotKey.Mods.command
    }
}
