import Carbon.HIToolbox

/// 基于 Carbon 的全局热键注册。
/// 支持动态「整体重挂」：设置变更后把全部热键一次性重新注册，避免逐个 diff。
/// 需要「辅助功能」权限才能生效。
final class GlobalHotKey {

    typealias Handler = () -> Void

    /// 一次热键登记
    struct Spec {
        let id: UInt32
        let keyCode: UInt32
        let modifiers: UInt32
        let handler: Handler
        init(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping Handler) {
            self.id = id
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.handler = handler
        }
    }

    enum Mods {
        static let option  = UInt32(optionKey)   // ⌥
        static let command = UInt32(cmdKey)      // ⌘
        static let shift   = UInt32(shiftKey)    // ⇧
        static let control = UInt32(controlKey)  // ⌃
    }

    private static var handlers: [UInt32: Handler] = [:]
    private static var refs: [UInt32: EventHotKeyRef] = [:]
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
        if status == noErr, let handler = handlers[stored.id] {
            handler()
        }
        return noErr
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

    /// 注销全部并重新按 specs 注册（幂等，可随时调用）
    static func apply(_ specs: [Spec]) {
        for (_, ref) in refs {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
        handlers.removeAll()

        installEventHandlerIfNeeded()

        for spec in specs {
            let hotKeyID = EventHotKeyID(signature: UInt32(0x41494657), id: spec.id)
            var hotKeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(
                spec.keyCode,
                spec.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if status == noErr, let ref = hotKeyRef {
                refs[spec.id] = ref
                handlers[spec.id] = spec.handler
            } else {
                NSLog("GlobalHotKey 注册失败: id=\(spec.id) key=\(spec.keyCode) mods=\(spec.modifiers) status=\(status)")
            }
        }
    }

    /// 是否已获得「辅助功能」权限（全局热键的前提）
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// 判断两套 (键码, 修饰键) 是否冲突（同一组合只能留一个）
    static func isConflicting(_ a: HotKeyBinding, _ b: HotKeyBinding) -> Bool {
        a.keyCode == b.keyCode && a.modifiers == b.modifiers
    }
}
