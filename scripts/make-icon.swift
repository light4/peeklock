// Renders the PeekLock app icon into an .iconset directory.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let args = CommandLine.arguments
guard args.count == 2 else {
  FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
  exit(2)
}
let outDir = URL(fileURLWithPath: args[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
  let size = CGFloat(pixels)
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

  let inset = size * 0.1
  let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
  let background = NSBezierPath(roundedRect: rect, xRadius: size * 0.2, yRadius: size * 0.2)
  NSGradient(
    starting: NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.95, alpha: 1),
    ending: NSColor(calibratedRed: 0.40, green: 0.20, blue: 0.85, alpha: 1))!
    .draw(in: background, angle: -90)

  let config = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .semibold)
    .applying(.init(paletteColors: [.white]))
  if let symbol = NSImage(systemSymbolName: "lock.display", accessibilityDescription: nil)?
    .withSymbolConfiguration(config)
  {
    let s = symbol.size
    symbol.draw(
      in: NSRect(
        x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
  }
  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
  try render(base).write(to: outDir.appendingPathComponent("icon_\(base)x\(base).png"))
  try render(base * 2).write(to: outDir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
