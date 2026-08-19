import Foundation

// ============================================================
// 数据模型（分组版）：网址组 → 组内多个网址
// ============================================================

/// 一个全局热键绑定（键码 + 修饰键掩码）
struct HotKeyBinding: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    var display: String {
        Self.modSymbols(for: modifiers) + Self.keyName(for: keyCode)
    }

    static func modSymbols(for mods: UInt32) -> String {
        var out = ""
        if mods & GlobalHotKey.Mods.control != 0 { out += "⌃" }
        if mods & GlobalHotKey.Mods.option != 0 { out += "⌥" }
        if mods & GlobalHotKey.Mods.shift != 0 { out += "⇧" }
        if mods & GlobalHotKey.Mods.command != 0 { out += "⌘" }
        return out
    }

    static func keyName(for code: UInt32) -> String {
        switch Int(code) {
        case 0...25: return String(UnicodeScalar(0x41 + code)!)   // A-Z
        case 18...26: return String(UnicodeScalar(0x31 + code - 18)!)  // 1-9
        case 27: return "0"
        case 36: return "↩"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "键\(code)"
        }
    }
}

/// 组内单个网址
struct SiteConfig: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var url: String

    init(id: UUID = UUID(), name: String, url: String) {
        self.id = id
        self.name = name
        self.url = url
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

/// 网址组：一个组 = 一个悬浮窗；组内多个网址用 ⌥⌘D/E 切换
struct GroupConfig: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var sites: [SiteConfig]
    var hotKey: HotKeyBinding?   // 呼出/切到此组的全局快捷键（默认无）
    var enabled: Bool            // 停用则不建窗口不吃内存
    var idleMinutes: Int?        // 组独立自动隐藏（nil=跟随全局）
    var frame: FrameSnapshot?    // 记住位置与尺寸
    var activeSiteIndex: Int     // 上次打开到组内第几个网址

    init(id: UUID = UUID(),
         name: String,
         sites: [SiteConfig],
         hotKey: HotKeyBinding? = nil,
         enabled: Bool = true,
         idleMinutes: Int? = nil,
         frame: FrameSnapshot? = nil,
         activeSiteIndex: Int = 0) {
        self.id = id
        self.name = name
        self.sites = sites
        self.hotKey = hotKey
        self.enabled = enabled
        self.idleMinutes = idleMinutes
        self.frame = frame
        self.activeSiteIndex = activeSiteIndex
    }

    func effectiveIdle(global: Int) -> Int {
        idleMinutes ?? global
    }

    /// 当前应展示的组内网址（越界安全）
    var safeActiveIndex: Int {
        sites.isEmpty ? 0 : min(max(activeSiteIndex, 0), sites.count - 1)
    }

    var activeSite: SiteConfig? {
        sites.isEmpty ? nil : sites[safeActiveIndex]
    }
}

/// 全局 ⌥⌘D / ⌥⌘E 两个键各自的动作
enum GlobalSwitchAction: Equatable {
    case next                 // 组内下一个网址
    case previous             // 组内上一个网址
    case specificGroup(UUID)  // 切到指定组
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
                self = .specificGroup(id)
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
        case .specificGroup(let id):
            try c.encode(Kind.specific, forKey: .kind)
            try c.encode(id, forKey: .id)
        }
    }
}

/// 全局设置
struct AppSettings: Codable, Equatable {
    var groups: [GroupConfig]
    var globalIdleMinutes: Int
    var dAction: GlobalSwitchAction
    var eAction: GlobalSwitchAction

    static func defaults() -> AppSettings {
        AppSettings(
            groups: [
                GroupConfig(name: "AI 助手", sites: [
                    SiteConfig(name: "豆包", url: "https://www.doubao.com/"),
                    SiteConfig(name: "DeepSeek", url: "https://chat.deepseek.com/"),
                ]),
            ],
            globalIdleMinutes: 15,
            dAction: .next,
            eAction: .previous
        )
    }
}
