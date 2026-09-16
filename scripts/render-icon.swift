import AppKit

let size = CGSize(width: 1024, height: 1024)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.09, green: 0.38, blue: 0.26, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
NSColor(calibratedRed: 0.95, green: 0.98, blue: 0.91, alpha: 1).setFill()
let leaf = NSBezierPath()
leaf.move(to: NSPoint(x: 255, y: 295))
leaf.curve(to: NSPoint(x: 768, y: 746), controlPoint1: NSPoint(x: 160, y: 690), controlPoint2: NSPoint(x: 480, y: 825))
leaf.curve(to: NSPoint(x: 255, y: 295), controlPoint1: NSPoint(x: 835, y: 365), controlPoint2: NSPoint(x: 620, y: 168))
leaf.fill()
NSColor(calibratedRed: 0.09, green: 0.38, blue: 0.26, alpha: 1).setStroke()
let check = NSBezierPath()
check.lineWidth = 54
check.lineCapStyle = .round
check.lineJoinStyle = .round
check.move(to: NSPoint(x: 356, y: 490))
check.line(to: NSPoint(x: 464, y: 388))
check.line(to: NSPoint(x: 660, y: 625))
check.stroke()
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon rendering failed") }
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try png.write(to: output, options: .atomic)
