import Foundation

/// 临时文本组的内容持久化：~/Library/Application Support/KanWindow/Text/<组UUID>.md
/// 文本组被自动关闭（dispose）或应用重启后，内容都从这里恢复。
enum TextStore {

    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("KanWindow/Text", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func fileURL(_ id: UUID) -> URL? {
        directory?.appendingPathComponent("\(id.uuidString).md")
    }

    /// 读取内容（不存在/读取失败时返回空串）
    static func load(_ id: UUID) -> String {
        guard let url = fileURL(id),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }

    /// 写入内容。同步写入：调用点（防抖落盘 / 隐藏 / 退出）频率很低，
    /// 且退出时必须确保最后一个字已经落盘，异步可能来不及。
    static func save(_ text: String, for id: UUID) {
        guard let url = fileURL(id) else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
