import Cocoa

// 程序入口：以「无 Dock 图标」的辅助工具方式运行（访问状态栏菜单）
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()
