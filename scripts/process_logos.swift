import Foundation
import AppKit

func findBoundingBox(image: NSImage) -> NSRect? {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let width = cgImage.width
    let height = cgImage.height
    
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = context.data else { return nil }
    let ptr = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
    
    var minX = width
    var maxX = 0
    var minY = height
    var maxY = 0
    var found = false
    
    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * width + x) * 4
            let alpha = ptr[offset + 3]
            if alpha > 10 { // Non-transparent threshold
                found = true
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
    }
    
    guard found, maxX >= minX, maxY >= minY else { return nil }
    
    // In CGContext, Y starts from bottom (0 is bottom). NSImage rect has 0,0 at bottom-left in Cocoa coordinate.
    let cropWidth = maxX - minX + 1
    let cropHeight = maxY - minY + 1
    return NSRect(x: minX, y: minY, width: cropWidth, height: cropHeight)
}

func cropAndPad(image: NSImage, paddingPercent: CGFloat = 0.03) -> NSImage {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let bbox = findBoundingBox(image: image) else { return image }
    
    let padX = bbox.width * paddingPercent
    let padY = bbox.height * paddingPercent
    
    let totalWidth = bbox.width + padX * 2
    let totalHeight = bbox.height + padY * 2
    
    let result = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
    result.lockFocus()
    
    NSGraphicsContext.current?.imageInterpolation = .high
    
    let sourceRect = bbox
    let destRect = NSRect(x: padX, y: padY, width: bbox.width, height: bbox.height)
    
    if let croppedCG = cgImage.cropping(to: CGRect(x: bbox.origin.x, y: CGFloat(cgImage.height) - bbox.origin.y - bbox.height, width: bbox.width, height: bbox.height)) {
        let rep = NSBitmapImageRep(cgImage: croppedCG)
        rep.draw(in: destRect)
    }
    
    result.unlockFocus()
    return result
}

func resize(image: NSImage, targetSize: NSSize, squarePad: Bool = false, safeZoneScale: CGFloat = 1.0) -> NSImage {
    let result = NSImage(size: targetSize)
    result.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    
    if squarePad {
        // Center image inside targetSize with aspect fit
        let imgW = image.size.width
        let imgH = image.size.height
        let scale = min(targetSize.width / imgW, targetSize.height / imgH) * safeZoneScale
        let drawW = imgW * scale
        let drawH = imgH * scale
        let drawX = (targetSize.width - drawW) / 2
        let drawY = (targetSize.height - drawH) / 2
        image.draw(in: NSRect(x: drawX, y: drawY, width: drawW, height: drawH), from: .zero, operation: .sourceOver, fraction: 1.0)
    } else {
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .sourceOver, fraction: 1.0)
    }
    
    result.unlockFocus()
    return result
}

func savePNG(image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("❌ Failed to save PNG to \(path)")
        return
    }
    try? pngData.write(to: URL(fileURLWithPath: path))
    print("✅ Saved: \(path)")
}

let fm = FileManager.default
let currentDir = fm.currentDirectoryPath
let logosDir = "\(currentDir)/logos"
let webAssetsDir = "\(logosDir)/web_assets"

try? fm.createDirectory(atPath: webAssetsDir, withIntermediateDirectories: true, attributes: nil)

// Load source images
guard let logo01 = NSImage(contentsOfFile: "\(logosDir)/AppNexa-01.png"),
      let logo02 = NSImage(contentsOfFile: "\(logosDir)/AppNexa-02.png"),
      let logo03 = NSImage(contentsOfFile: "\(logosDir)/AppNexa-03.png"),
      let logoWhite02 = NSImage(contentsOfFile: "\(logosDir)/AppNexa white-02.png"),
      let logoWhite03 = NSImage(contentsOfFile: "\(logosDir)/AppNexa white-03.png"),
      let logoBlack02 = NSImage(contentsOfFile: "\(logosDir)/AppNexa black-02.png"),
      let logoBlack03 = NSImage(contentsOfFile: "\(logosDir)/AppNexa black-03.png") else {
    print("❌ Failed to load source images from \(logosDir)")
    exit(1)
}

print("🔨 Processing and cropping master logo assets...")

// Crop images
let croppedLogo03 = cropAndPad(image: logo03, paddingPercent: 0.02)
let croppedLogo01 = cropAndPad(image: logo01, paddingPercent: 0.02)
let croppedLogo02 = cropAndPad(image: logo02, paddingPercent: 0.02)
let croppedWhite03 = cropAndPad(image: logoWhite03, paddingPercent: 0.02)
let croppedWhite02 = cropAndPad(image: logoWhite02, paddingPercent: 0.02)
let croppedBlack03 = cropAndPad(image: logoBlack03, paddingPercent: 0.02)
let croppedBlack02 = cropAndPad(image: logoBlack02, paddingPercent: 0.02)

// Save cropped master web assets
savePNG(image: croppedLogo03, to: "\(webAssetsDir)/appnexa-logo-full.png")
savePNG(image: croppedWhite03, to: "\(webAssetsDir)/appnexa-logo-white.png")
savePNG(image: croppedBlack03, to: "\(webAssetsDir)/appnexa-logo-black.png")
savePNG(image: croppedLogo01, to: "\(webAssetsDir)/appnexa-logo-tagline.png")
savePNG(image: croppedLogo02, to: "\(webAssetsDir)/appnexa-icon.png")
savePNG(image: croppedWhite02, to: "\(webAssetsDir)/appnexa-icon-white.png")
savePNG(image: croppedBlack02, to: "\(webAssetsDir)/appnexa-icon-black.png")

// Generate Standard Icons & Favicons
print("\n🔨 Generating standard PWA icons and favicons...")
let icon16 = resize(image: croppedLogo02, targetSize: NSSize(width: 16, height: 16), squarePad: true)
let icon32 = resize(image: croppedLogo02, targetSize: NSSize(width: 32, height: 32), squarePad: true)
let icon48 = resize(image: croppedLogo02, targetSize: NSSize(width: 48, height: 48), squarePad: true)
let icon180 = resize(image: croppedLogo02, targetSize: NSSize(width: 180, height: 180), squarePad: true, safeZoneScale: 0.9)
let icon192 = resize(image: croppedLogo02, targetSize: NSSize(width: 192, height: 192), squarePad: true, safeZoneScale: 0.88)
let icon512 = resize(image: croppedLogo02, targetSize: NSSize(width: 512, height: 512), squarePad: true, safeZoneScale: 0.88)

// Maskable icons (requires more padding for circular/squircle cuts: ~75% safe area)
let maskable192 = resize(image: croppedLogo02, targetSize: NSSize(width: 192, height: 192), squarePad: true, safeZoneScale: 0.72)
let maskable512 = resize(image: croppedLogo02, targetSize: NSSize(width: 512, height: 512), squarePad: true, safeZoneScale: 0.72)

savePNG(image: icon16, to: "\(webAssetsDir)/favicon-16x16.png")
savePNG(image: icon32, to: "\(webAssetsDir)/favicon-32x32.png")
savePNG(image: icon48, to: "\(webAssetsDir)/favicon-48x48.png")
savePNG(image: icon32, to: "\(webAssetsDir)/favicon.png")
savePNG(image: icon180, to: "\(webAssetsDir)/apple-touch-icon.png")
savePNG(image: icon192, to: "\(webAssetsDir)/Icon-192.png")
savePNG(image: icon512, to: "\(webAssetsDir)/Icon-512.png")
savePNG(image: maskable192, to: "\(webAssetsDir)/Icon-maskable-192.png")
savePNG(image: maskable512, to: "\(webAssetsDir)/Icon-maskable-512.png")

// Copy to destinations
let destinationDirs = [
    "\(currentDir)/landing_page/assets/images",
    "\(currentDir)/admin_panel/assets/images",
    "\(currentDir)/admin_panel/web/icons",
    "\(currentDir)/review_page/assets/images"
]

for dir in destinationDirs {
    try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
}

// Copy to landing_page
savePNG(image: croppedLogo03, to: "\(currentDir)/landing_page/assets/images/appnexa-logo-full.png")
savePNG(image: croppedWhite03, to: "\(currentDir)/landing_page/assets/images/appnexa-logo-white.png")
savePNG(image: croppedLogo02, to: "\(currentDir)/landing_page/assets/images/appnexa-icon.png")
savePNG(image: icon32, to: "\(currentDir)/landing_page/favicon.png")
savePNG(image: icon32, to: "\(currentDir)/landing_page/favicon.ico")
savePNG(image: icon180, to: "\(currentDir)/landing_page/apple-touch-icon.png")

// Copy to admin_panel
savePNG(image: croppedLogo03, to: "\(currentDir)/admin_panel/assets/images/appnexa-logo-full.png")
savePNG(image: croppedWhite03, to: "\(currentDir)/admin_panel/assets/images/appnexa-logo-white.png")
savePNG(image: croppedLogo02, to: "\(currentDir)/admin_panel/assets/images/appnexa-icon.png")
savePNG(image: icon32, to: "\(currentDir)/admin_panel/web/favicon.png")
savePNG(image: icon192, to: "\(currentDir)/admin_panel/web/icons/Icon-192.png")
savePNG(image: icon512, to: "\(currentDir)/admin_panel/web/icons/Icon-512.png")
savePNG(image: maskable192, to: "\(currentDir)/admin_panel/web/icons/Icon-maskable-192.png")
savePNG(image: maskable512, to: "\(currentDir)/admin_panel/web/icons/Icon-maskable-512.png")

// Copy to review_page
savePNG(image: croppedLogo02, to: "\(currentDir)/review_page/assets/images/appnexa-icon.png")
savePNG(image: croppedLogo03, to: "\(currentDir)/review_page/assets/images/appnexa-logo-full.png")
savePNG(image: icon32, to: "\(currentDir)/review_page/favicon.png")

print("\n✨ All logo variants cropped, generated, and copied successfully!")
