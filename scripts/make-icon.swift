import AppKit

// 一键生成 App 图标：绘制 1024x1024 圆角背景 + “AI” 字样
// 用法: swift make-icon.swift <输出.png>
let args = CommandLine.arguments
guard args.count > 1 else { fatalError("用法: swift make-icon.swift <输出路径>") }
let outputPath = args[1]

let side: CGFloat = 1024
let image = NSImage(size: NSSize(width: side, height: side))
image.lockFocus()

// 主背景（圆角蓝色）
let background = NSBezierPath(
    roundedRect: NSRect(x: 0, y: 0, width: side, height: side),
    xRadius: 220, yRadius: 220
)
NSColor(calibratedRed: 0.11, green: 0.53, blue: 1.00, alpha: 1).setFill()
background.fill()

// 左下角气泡圆点
let bubble = NSBezierPath(ovalIn: NSRect(x: 128, y: 128, width: 200, height: 200))
NSColor(calibratedRed: 0.34, green: 0.72, blue: 1.00, alpha: 0.9).setFill()
bubble.fill()

// “AI” 白字
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 460, weight: .bold),
    .foregroundColor: NSColor.white,
]
let text = "AI" as NSString
let textSize = text.size(withAttributes: attrs)
text.draw(
    at: NSPoint(x: (side - textSize.width) / 2, y: (side - textSize.height) / 2 - 30),
    withAttributes: attrs
)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let data = rep.representation(using: .png, properties: [:])
else { fatalError("渲染失败") }

do {
    try data.write(to: URL(fileURLWithPath: outputPath))
    print("✔ 已生成: \(outputPath)")
} catch {
    fatalError("写入失败: \(error)")
}
