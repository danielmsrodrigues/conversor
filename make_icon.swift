// Desenha o ícone da app (1024×1024) e grava-o como PNG.
// Uso: swiftc make_icon.swift -o make_icon && ./make_icon saida.png
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Fundo: gradiente que ocupa a tela toda (o macOS aplica a forma arredondada).
let canvas = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(colors: [NSColor(red: 0.36, green: 0.30, blue: 0.95, alpha: 1),
                    NSColor(red: 0.93, green: 0.30, blue: 0.62, alpha: 1)])!
    .draw(in: NSBezierPath(rect: canvas), angle: -55)

// Anel de pontos — o seletor redondo.
let center = NSPoint(x: size / 2, y: size / 2)
let ringRadius: CGFloat = 330
for i in 0..<8 {
    let angle = CGFloat(i) / 8 * 2 * .pi + .pi / 2
    let dot: CGFloat = 92
    let p = NSPoint(x: center.x + cos(angle) * ringRadius - dot / 2, y: center.y + sin(angle) * ringRadius - dot / 2)
    NSColor.white.withAlphaComponent(i == 0 ? 0.95 : 0.35).setFill()
    NSBezierPath(ovalIn: NSRect(origin: p, size: NSSize(width: dot, height: dot))).fill()
}

// Setas no centro.
let config = NSImage.SymbolConfiguration(pointSize: 330, weight: .semibold)
    .applying(.init(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = symbol.size
    symbol.draw(in: NSRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height))
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
