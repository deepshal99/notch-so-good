#!/usr/bin/env swift
// Generates Chawd app icon PNGs for the asset catalog
import AppKit
import CoreGraphics

func drawChawd(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    // Flip to top-left origin
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)

    // Background: dark gradient
    let bgColors = [
        CGColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1),
        CGColor(red: 0.12, green: 0.10, blue: 0.14, alpha: 1)
    ]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: bgColors as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: size/2, y: 0),
                           end: CGPoint(x: size/2, y: size),
                           options: [])

    // Chawd colors
    let skin = CGColor(red: 0.77, green: 0.54, blue: 0.42, alpha: 1)       // C4896C
    let skinLight = CGColor(red: 0.83, green: 0.60, blue: 0.49, alpha: 0.3) // D49A7C
    let skinDark = CGColor(red: 0.69, green: 0.48, blue: 0.37, alpha: 1)   // B07A5E
    let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    let blush = CGColor(red: 0.91, green: 0.46, blue: 0.42, alpha: 0.25)

    // Grid: Chawd is ~18x15 grid units. Scale to fit nicely in icon.
    // Leave ~25% padding on each side
    let px = size / 26.0
    let gridW: CGFloat = 18 * px
    let gridH: CGFloat = 15 * px
    let ox = (size - gridW) / 2
    let oy = (size - gridH) / 2 - px * 0.5  // nudge up slightly

    func fill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: CGColor) {
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: ox + x * px, y: oy + y * px, width: w * px, height: h * px))
    }

    // Left arm/claw
    fill(0, 2, 3, 4, skin)

    // Main body
    fill(3, 0, 14, 9, skin)

    // Highlight on top
    fill(3, 0, 14, 1, skinLight)

    // Eyes — default waving/friendly style
    fill(7, 2, 1, 3, black)
    fill(12, 2, 1, 3, black)

    // Gentle smile
    fill(9, 6.5, 2.5, 0.8, skinDark)

    // Cheek blush
    fill(5, 5, 2, 1.5, blush)
    fill(13.5, 5, 2, 1.5, blush)

    // Left leg
    fill(6, 9, 2, 4, skin)
    fill(6, 12, 2, 1, skinDark)

    // Right leg
    fill(12, 9, 2, 4, skin)
    fill(12, 12, 2, 1, skinDark)

    // Subtle glow under Chawd
    ctx.setFillColor(CGColor(red: 0.75, green: 0.52, blue: 0.80, alpha: 0.08))
    let glowRect = CGRect(x: ox + 3 * px, y: oy + 14 * px, width: 14 * px, height: 2 * px)
    ctx.fillEllipse(in: glowRect)

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG for \(path)")
        return
    }
    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        print("  ✓ \(path.split(separator: "/").last ?? "")")
    } catch {
        print("  ✗ Failed: \(error)")
    }
}

// Required macOS icon sizes
let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

let outputDir = "NotchSoGood/Assets.xcassets/AppIcon.appiconset"

print("Generating Chawd app icons...")
for (name, pixels) in sizes {
    let image = drawChawd(size: CGFloat(pixels))
    savePNG(image, to: "\(outputDir)/\(name)")
}

// Update Contents.json
let contentsJSON = """
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""

try! contentsJSON.write(toFile: "\(outputDir)/Contents.json", atomically: true, encoding: .utf8)
print("✅ All icons generated and Contents.json updated")
