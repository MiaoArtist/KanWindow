import AppKit

// 把「黑=不透明、白=挖洞」的矢量渲染图转成真正的模板 PNG：
//   alpha = 255 - 亮度（黑→不透明，白→全透明），统一黑色通道。
// qlmanage 会把透明压成白底，所以这里直接按像素重建 alpha 通道。
// 用法: swift template-png.swift <输入.png> <输出.png>
let args = CommandLine.arguments
guard args.count >= 3 else { fatalError("用法: swift template-png.swift <输入.png> <输出.png>") }
let inputURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])

guard let image = NSImage(contentsOf: inputURL) else { fatalError("读取图片失败") }
let w = Int(image.size.width)
let h = Int(image.size.height)

guard let out = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: w, pixelsHigh: h,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { fatalError("无法创建位图") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: w, height: h).fill()
image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
NSGraphicsContext.restoreGraphicsState()

guard let data = out.bitmapData else { fatalError("无像素数据") }
let bpr = out.bytesPerRow
for y in 0..<h {
    var p = data + y * bpr
    for _ in 0..<w {
        let r = Double(p[0]) / 255.0
        let b = Double(p[2]) / 255.0
        let lum = 0.299 * r + 0.587 * (Double(p[1]) / 255.0) + 0.114 * b
        let a = UInt8(max(0, min(255, Int(((1.0 - lum) * 255.0).rounded()))))
        p[0] = 0
        p[1] = 0
        p[2] = 0
        p[3] = a
        p += 4
    }
}

guard let png = out.representation(using: .png, properties: [:]) else { fatalError("编码失败") }
try? png.write(to: outputURL)
print("✔ 模板图标: \(outputURL.path)")
