import AppKit
// Icon Composer 렌더(몸체가 가득 찬 1024 이미지)를 예전 macOS 아이콘 규격으로 옮긴다:
// 1024 캔버스 가운데 824 크기 + 아래쪽 그림자. 사용법: make_legacy_icons <render.png> <appiconset 폴더>
let args = CommandLine.arguments
let source = NSImage(contentsOfFile: args[1])!
let outDir = args[2]

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    let k = CGFloat(px) / 1024
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -10 * k)
    shadow.shadowBlurRadius = 20 * k
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.set()
    source.draw(in: NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                   ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
                   ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("ok")
