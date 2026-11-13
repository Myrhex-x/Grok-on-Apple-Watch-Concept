// Draws the app icon: three white dots on black, the "Grok is writing" mark (answers come as
// text, never speech). watchOS crops it to a circle.
//
//   swift Tools/make-icon.swift GrokWatch/Assets.xcassets/AppIcon.appiconset/icon-1024.png

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = CommandLine.arguments.dropFirst().first ?? "icon-1024.png"
let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("no context")
}

context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

let diameter: CGFloat = 150
let gap: CGFloat = 64
let total = diameter * 3 + gap * 2
let startX = (CGFloat(size) - total) / 2
let y = (CGFloat(size) - diameter) / 2
// Bright to dim, like one frame of the typing dots.
for (index, alpha) in [1.0, 0.62, 0.32].enumerated() {
    let x = startX + CGFloat(index) * (diameter + gap)
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha))
    context.fillEllipse(in: CGRect(x: x, y: y, width: diameter, height: diameter))
}

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("no image")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("write failed") }
print("wrote \(output)")
