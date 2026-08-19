import Carbon.HIToolbox

/// 基于 Carbon 的全局热键注册。
/// 无论焦点在哪个 App 都能触发；需要「辅助功能」权限才能生效。
final class GlobalHotKey {

    typealias Handler = () -> Void

    enum Mods {
        static let option  = UInt32(optionKey)   // ⌥
        static let command = UInt32(cmdKey)      // ⌘
        static let shift   = UInt32(shiftKey)    // ⇧
        static let control = UInt32(controlKey)  // ⌃
    }

    private static var registry: [UInt32: Handler] = [:]
    private static var hotKeyRefs: [EventHotKeyRef] = []
    private static var eventHandlerInstalled = false

    // 统一的按键回调（不捕获任何变量，符合 C 函数指针要求）
    private static let eventHandler: EventHandlerUPP = { _, event, _ in
        var stored = EventHotKeyID()
        var actualSize = 0
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            &actualSize,
            &stored
        )
        if status == noErr, let handler = registry[stored.id] {
            handler()
        }
        return noErr
    }

    /// 注册一个全局热键。
    /// - Parameters:
    ///   - keyCode: 键码（Space=49，D=2，E=14）
    ///   - modifiers: 修饰键（Mods 组合）
    ///   - id: 唯一 ID（用于回调定位）
    @discardableResult
    static func register(keyCode: UInt32,
                         modifiers: UInt32,
                         id: UInt32,
                         handler: @escaping Handler) -> Bool {
        // 事件处理器只需安装一次（macOS 同处理器重复安装会报错）
        installEventHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: UInt32(0x41494657), id: id)
        var hotKeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let ref = hotKeyRef else {
            NSLog("GlobalHotKey 注册失败: keyCode=\(keyCode) mods=\(modifiers) status=\(status)")
            return false
        }

        registry[id] = handler
        hotKeyRefs.append(ref)
        return true
    }

    /// 安装统一的按键回调（全局只装一次）
    private static func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            eventHandler,
            1,
            &eventType,
            nil,
            nil
        )
        if status == noErr {
            eventHandlerInstalled = true
        } else {
            NSLog("GlobalHotKey 事件处理器安装失败: status=\(status)")
        }
    }

    /// 是否已获得「辅助功能」权限（全局热键的前提）。
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }
}
