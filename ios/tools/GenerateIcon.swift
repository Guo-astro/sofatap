// Original vector icon, generated with the macOS SDK. No external asset dependencies.
import AppKit
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                             isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(red: 0.039, green: 0.051, blue: 0.067, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
let mint = NSColor(red: 0.722, green: 0.953, blue: 0.816, alpha: 1)
mint.setFill()
NSBezierPath(roundedRect: NSRect(x: 230, y: 428, width: 564, height: 294), xRadius: 66, yRadius: 66).fill()
NSBezierPath(roundedRect: NSRect(x: 139, y: 294, width: 155, height: 283), xRadius: 57, yRadius: 57).fill()
NSBezierPath(roundedRect: NSRect(x: 730, y: 294, width: 155, height: 283), xRadius: 57, yRadius: 57).fill()
NSBezierPath(roundedRect: NSRect(x: 223, y: 279, width: 578, height: 154), xRadius: 34, yRadius: 34).fill()
NSBezierPath(roundedRect: NSRect(x: 230, y: 230, width: 54, height: 112), xRadius: 22, yRadius: 22).fill()
NSBezierPath(roundedRect: NSRect(x: 740, y: 230, width: 54, height: 112), xRadius: 22, yRadius: 22).fill()
NSColor(red: 0.039, green: 0.051, blue: 0.067, alpha: 1).setStroke()
let seam = NSBezierPath()
seam.move(to: NSPoint(x: 512, y: 450)); seam.line(to: NSPoint(x: 512, y: 683))
seam.lineWidth = 12; seam.lineCapStyle = .round; seam.stroke()
NSGraphicsContext.restoreGraphicsState()
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Tiltro/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
