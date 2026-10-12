import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Format conversion only. Preserve the complete approved AppIcon composition.
// Run on macOS; the generated ICO is committed so Windows builds need no image tools.
guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: xcrun swift scripts/generate-windows-icon.swift SOURCE.png DESTINATION.ico")
}
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let destinationURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      image.width == image.height else { fatalError("Expected a square source image") }

let sizes = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
let frames: [Data] = sizes.map { size in
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("Cannot create icon bitmap") }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    let png = NSMutableData()
    guard let frame = context.makeImage(),
          let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("Cannot create icon PNG") }
    CGImageDestinationAddImage(destination, frame, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot encode icon PNG") }
    return png as Data
}

extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ number: T) {
        var value = number.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
var ico = Data()
ico.appendLittleEndian(UInt16(0))
ico.appendLittleEndian(UInt16(1))
ico.appendLittleEndian(UInt16(sizes.count))
var offset = 6 + sizes.count * 16
for (size, png) in zip(sizes, frames) {
    let dimension = UInt8(size == 256 ? 0 : size)
    ico.append(contentsOf: [dimension, dimension, 0, 0])
    ico.appendLittleEndian(UInt16(1))
    ico.appendLittleEndian(UInt16(32))
    ico.appendLittleEndian(UInt32(png.count))
    ico.appendLittleEndian(UInt32(offset))
    offset += png.count
}
frames.forEach { ico.append($0) }
try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try ico.write(to: destinationURL, options: .atomic)
print("Converted the full source artwork into \(sizes.count) Windows icon sizes.")
