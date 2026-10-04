// Renders the app icon (a keyboard on a rounded square) into an .iconset.
// Usage: swift make-icon.swift <output.iconset>

import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(_ size: Int) -> Data {
    let pixels = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: the shape fills ~80% of the canvas.
    let inset = pixels * 0.1
    let box = NSRect(x: inset, y: inset, width: pixels - inset * 2, height: pixels - inset * 2)
    let shape = NSBezierPath(roundedRect: box, xRadius: box.width * 0.225, yRadius: box.width * 0.225)
    NSGradient(starting: NSColor(red: 0.36, green: 0.42, blue: 0.95, alpha: 1),
               ending: NSColor(red: 0.20, green: 0.22, blue: 0.62, alpha: 1))!.draw(in: shape, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: box.width * 0.42, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    let symbol = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    let symbolSize = symbol.size
    symbol.draw(in: NSRect(x: (pixels - symbolSize.width) / 2, y: (pixels - symbolSize.height) / 2,
                           width: symbolSize.width, height: symbolSize.height))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: output.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: output.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
