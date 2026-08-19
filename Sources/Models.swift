import Foundation

// ============================================================
// 数据模型（v0.4）：网址组 / 统一全局快捷键
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
        // 特殊键
        switch Int(code) {
        case 36: return "↩"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: break
        }
        // ANSI 虚拟键码表（注意：字母不是按 A-Z 顺序，如 D=2 / E=14 / C=8）
        let ansi: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "5",
            23: "6", 24: "7", 25: "8", 26: "9", 27: "0", 28: "-", 29: "=",
            31: "O", 32: "U", 33: "[", 34: "]", 35: "\\", 37: "L", 38: ";",
            39: "'", 40: "`", 41: "§", 43: ",", 44: "/", 45: "N", 46: "M",
            47: ".", 50: "`",
        ]
        if let c = ansi[code] {
            return c
        }
        return "键\(code)"
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

/// 网址组：一个组 = 一个悬浮窗；组内多个网址用快捷键在组内切换
struct GroupConfig: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var sites: [SiteConfig]
    var enabled: Bool            // 停用则不建窗口不吃内存
    var idleMinutes: Int?        // 组独立自动关闭分钟数（nil=跟随全局）
    var frame: FrameSnapshot?    // 记住位置与尺寸
    var activeSiteIndex: Int     // 上次打开到组内第几个网址

    init(id: UUID = UUID(),
         name: String,
         sites: [SiteConfig],
         enabled: Bool = true,
         idleMinutes: Int? = nil,
         frame: FrameSnapshot? = nil,
         activeSiteIndex: Int = 0) {
        self.id = id
        self.name = name
        self.sites = sites
        self.enabled = enabled
        self.idleMinutes = idleMinutes
        self.frame = frame
        self.activeSiteIndex = activeSiteIndex
    }

    func effectiveIdle(global: Int) -> Int {
        idleMinutes ?? global
    }

    var safeActiveIndex: Int {
        sites.isEmpty ? 0 : min(max(activeSiteIndex, 0), sites.count - 1)
    }

    var activeSite: SiteConfig? {
        sites.isEmpty ? nil : sites[safeActiveIndex]
    }
}

/// 一条统一全局快捷键：绑定一个“功能”
struct HotkeyConfig: Codable, Equatable, Identifiable {
    var id: UUID
    var function: HotkeyFunction
    var binding: HotKeyBinding?   // nil = 还没录按键（登记后生效）

    init(id: UUID = UUID(), function: HotkeyFunction, binding: HotKeyBinding? = nil) {
        self.id = id
        self.function = function
        self.binding = binding
    }
}

/// 快捷键可以实现的功能
enum HotkeyFunction: Equatable {
    case toggleCurrent      // 显示/隐藏当前组
    case nextSite           // 组内下一个网址
    case previousSite       // 组内上一个网址
    case nextGroup          // 切换下一个组
    case previousGroup      // 切换上一个组
    case specificGroup(UUID)// 切换至指定组
    case refresh            // 刷新当前浮窗
}

extension HotkeyFunction {
    /// 序列化用标记
    var tag: String {
        switch self {
        case .toggleCurrent: return "toggle"
        case .nextSite: return "nextSite"
        case .previousSite: return "previousSite"
        case .nextGroup: return "nextGroup"
        case .previousGroup: return "previousGroup"
        case .specificGroup(let id): return "specific:\(id.uuidString)"
        case .refresh: return "refresh"
        }
    }

    static func fromTag(_ tag: String) -> HotkeyFunction? {
        switch tag {
        case "toggle": return .toggleCurrent
        case "nextSite": return .nextSite
        case "previousSite": return .previousSite
        case "nextGroup": return .nextGroup
        case "previousGroup": return .previousGroup
        case "refresh": return .refresh
        default:
            if tag.hasPrefix("specific:"),
               let id = UUID(uuidString: String(tag.dropFirst("specific:".count))) {
                return .specificGroup(id)
            }
            return nil
        }
    }

    /// 简短标题（切组类需要组名时由调用方补全）
    var display: String {
        switch self {
        case .toggleCurrent: return "显示/隐藏当前组"
        case .nextSite: return "组内下一个网址"
        case .previousSite: return "组内上一个网址"
        case .nextGroup: return "切换下一个组"
        case .previousGroup: return "切换上一个组"
        case .specificGroup: return "切换至某组"
        case .refresh: return "刷新当前浮窗"
        }
    }
}

extension HotkeyFunction: Codable {
    private enum Kind: String, Codable {
        case toggle, nextSite, previousSite, nextGroup, previousGroup, specific, refresh
    }
    private enum CodingKeys: String, CodingKey { case kind, id }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .toggle: self = .toggleCurrent
        case .nextSite: self = .nextSite
        case .previousSite: self = .previousSite
        case .nextGroup: self = .nextGroup
        case .previousGroup: self = .previousGroup
        case .refresh: self = .refresh
        case .specific:
            if let id = try? c.decode(UUID.self, forKey: .id) {
                self = .specificGroup(id)
            } else {
                self = .toggleCurrent
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .toggleCurrent: try c.encode(Kind.toggle, forKey: .kind)
        case .nextSite: try c.encode(Kind.nextSite, forKey: .kind)
        case .previousSite: try c.encode(Kind.previousSite, forKey: .kind)
        case .nextGroup: try c.encode(Kind.nextGroup, forKey: .kind)
        case .previousGroup: try c.encode(Kind.previousGroup, forKey: .kind)
        case .refresh: try c.encode(Kind.refresh, forKey: .kind)
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
    var hotkeys: [HotkeyConfig]

    static func defaults() -> AppSettings {
        AppSettings(
            groups: [
                GroupConfig(name: "AI 助手", sites: [
                    SiteConfig(name: "豆包", url: "https://www.doubao.com/"),
                    SiteConfig(name: "DeepSeek", url: "https://chat.deepseek.com/"),
                ]),
            ],
            globalIdleMinutes: 15,
            hotkeys: [
                HotkeyConfig(
                    function: .toggleCurrent,
                    binding: HotKeyBinding(keyCode: Config.HotKey.toggleKeyCode,
                                            modifiers: Config.HotKey.toggleModifiers)),
                HotkeyConfig(
                    function: .nextSite,
                    binding: HotKeyBinding(keyCode: Config.HotKey.switchKeyCodeD,
                                            modifiers: Config.HotKey.switchModifiers)),
                HotkeyConfig(
                    function: .previousSite,
                    binding: HotKeyBinding(keyCode: Config.HotKey.switchKeyCodeE,
                                            modifiers: Config.HotKey.switchModifiers)),
            ]
        )
    }
}
