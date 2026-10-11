// Рисует иконку приложения 1024×1024 в PNG: swift scripts/make-icon.swift out.png
import AppKit

let size = 1024
guard CommandLine.arguments.count > 1 else {
    print("usage: make-icon.swift <out.png>")
    exit(1)
}

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Сетка иконок macOS: плитка 824×824 по центру холста.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor.black.setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()

let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.16, green: 0.80, blue: 0.62, alpha: 1),
    NSColor(srgbRed: 0.15, green: 0.52, blue: 0.95, alpha: 1),
])!
gradient.draw(in: tilePath, angle: -50)

if let symbol = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: 400, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let image = symbol.withSymbolConfiguration(config) {
        let s = image.size
        let rect = NSRect(x: (CGFloat(size) - s.width) / 2 + 10, y: (CGFloat(size) - s.height) / 2,
                          width: s.width, height: s.height)
        image.draw(in: rect)
    }
}

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
