import Foundation

// ============================================================
// 数据模型：浮窗配置 / 全局设置 / 热键绑定
// ============================================================

/// 一个全局热键绑定（键码 + 修饰键掩码）
struct HotKeyBinding: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    /// 可读显示，如 "⌥⌘D"
    var display: String {
        Self.modSymbols(for: modifiers) + Self.keyName(for: keyCode)
    }

    /// 修饰键掩码（与 GlobalHotKey.Mods 一致）：⌃⌥⇧⌘
    static func modSymbols(for mods: UInt32) -> String {
        var out = ""
        if mods & GlobalHotKey.Mods.control != 0 { out += "⌃" }
        if mods & GlobalHotKey.Mods.option != 0 { out += "⌥" }
        if mods & GlobalHotKey.Mods.shift != 0 { out += "⇧" }
        if mods & GlobalHotKey.Mods.command != 0 { out += "⌘" }
        return out
    }

    static func keyName(for code: UInt32) -> String {
        // 常见键
        switch Int(code) {
        case 0...25: return String(UnicodeScalar(0x41 + code)!)  // A-Z
        case 18...26: return String(UnicodeScalar(0x31 + code - 18)!)  // 1-9
        case 27: return "0"
        case 36: return "↩"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "Esc"
        case 96: return "F5"
        default: return "键\(code)"
        }
    }
}

/// 单个悬浮窗的配置
struct PaneConfig: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var url: String
    var hotKey: HotKeyBinding?     // 该浮窗专属的全局快捷键（默认无）
    var enabled: Bool              // 启用/停用（停用不建窗口不吃内存）
    var idleMinutes: Int?          // 每浮窗独立自动隐藏分钟数（nil=跟随全局）
    var frame: FrameSnapshot?      // 记住上次的位置与尺寸

    init(id: UUID = UUID(),
         name: String,
         url: String,
         hotKey: HotKeyBinding? = nil,
         enabled: Bool = true,
         idleMinutes: Int? = nil,
         frame: FrameSnapshot? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.hotKey = hotKey
        self.enabled = enabled
        self.idleMinutes = idleMinutes
        self.frame = frame
    }

    /// 有效自动隐藏分钟数（nil→跟随全局；0 或负数→不自动隐藏）
    func effectiveIdle(global: Int) -> Int {
        idleMinutes ?? global
    }
}

/// 窗口位置尺寸快照
struct FrameSnapshot: Codable, Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    init(from rect: NSRect) {
        x = Double(rect.origin.x)
        y = Double(rect.origin.y)
        w = Double(rect.size.width)
        h = Double(rect.size.height)
    }

    var rect: NSRect {
        get { NSRect(x: x, y: y, width: w, height: h) }
        set {
            x = Double(newValue.origin.x)
            y = Double(newValue.origin.y)
            w = Double(newValue.size.width)
            h = Double(newValue.size.height)
        }
    }
}

/// 全局 ⌥⌘D / ⌥⌘E 两个键各自的动作
enum GlobalSwitchAction: Equatable {
    case next          // 下一个浮窗
    case previous      // 上一个浮窗
    case specific(UUID) // 切到指定浮窗
    case none
}

extension GlobalSwitchAction: Codable {
    private enum Kind: String, Codable { case next, previous, specific, none }
    private enum CodingKeys: String, CodingKey { case kind, id }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .next: self = .next
        case .previous: self = .previous
        case .none: self = .none
        case .specific:
            if let id = try? c.decode(UUID.self, forKey: .id) {
                self = .specific(id)
            } else {
                self = .none
            }
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

}

/// 全局设置
struct AppSettings: Codable, Equatable {
    var panes: [PaneConfig]
    var globalIdleMinutes: Int
    var dAction: GlobalSwitchAction
    var eAction: GlobalSwitchAction

    static func defaults() -> AppSettings {
        AppSettings(
            panes: [
                PaneConfig(name: "豆包", url: "https://www.doubao.com/"),
                PaneConfig(name: "DeepSeek", url: "https://chat.deepseek.com/"),
            ],
            globalIdleMinutes: 15,
            dAction: .next,
            eAction: .previous
        )
    }
}
