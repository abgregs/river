import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import River

/// Renders the mark's menu bar PNGs from `StoneMark` (docs/design/stones-identity.md). This is
/// the checked-in script: `RIVER_WRITE_GLYPHS=1 swift test --filter MenuBarGlyph` regenerates
/// the assets; the normal suite checks the shipped files still match, so a shape edit without
/// a regeneration fails.
enum MenuBarGlyphRenderer {
    static let assetDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/River/Resources/MenuBarGlyphs")

    /// Every shipped image: the glyph, its appearance, and its asset name.
    static let images: [(glyph: MenuBarPresentation.Glyph, dark: Bool, name: String)] =
        MenuBarPresentation.Glyph.allCases.flatMap { glyph in
            (glyph.isTemplate ? [false] : [false, true]).map { dark in (glyph, dark, glyph.assetName(dark: dark)) }
        }

    static func fileName(_ name: String, scale: Int) -> String {
        scale == 1 ? "\(name).png" : "\(name)@\(scale)x.png"
    }

    static func outlines(for glyph: MenuBarPresentation.Glyph) -> [[StoneMark.Point]] {
        switch glyph {
        case .ready: return StoneMark.pieces
        case .active: return Constants.menuBarActiveLevels.enumerated().map { StoneMark.bar($0.offset, level: $0.element) }
        }
    }

    // Ready is black with alpha, read by its alpha only as a template image. Active is the
    // accent for the menu bar's appearance: the light value on a light bar, the dark on a dark.
    static func color(for glyph: MenuBarPresentation.Glyph, dark: Bool) -> CGColor {
        switch glyph {
        case .ready: return CGColor(gray: 0, alpha: 1)
        case .active: return (dark ? Palette.accentDark : Palette.accentLight).cgColor
        }
    }

    // The glyph's own shapes, 16 pt tall and centered in the 18 pt box.
    static func render(_ glyph: MenuBarPresentation.Glyph, dark: Bool, scale: Int) throws -> CGImage {
        let size = Constants.menuBarGlyphSize
        let pixels = Int(size) * scale
        struct ContextUnavailable: Error {}
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ContextUnavailable() }
        // Top-left origin in points, matching the design units' y-down.
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        context.setShouldAntialias(true)
        let outlines = outlines(for: glyph)
        let box = StoneMark.boundingBox(outlines)
        let height = Constants.menuBarMarkHeight
        let target = CGRect(x: (size - box.width * height / box.height) / 2, y: (size - height) / 2,
                            width: box.width * height / box.height, height: height)
        let transform = StoneMark.transform(fitting: box, into: target)
        context.setFillColor(color(for: glyph, dark: dark))
        for outline in outlines { context.addPath(StoneMark.path(outline, transform: transform)) }
        context.fillPath()
        guard let image = context.makeImage() else { throw ContextUnavailable() }
        return image
    }

    static func rgba(of image: CGImage) -> [UInt8] {
        let rep = NSBitmapImageRep(cgImage: image)
        return (0..<rep.pixelsHigh).flatMap { y in
            (0..<rep.pixelsWide).flatMap { x -> [UInt8] in
                let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                return [color?.redComponent, color?.greenComponent, color?.blueComponent, color?.alphaComponent]
                    .map { UInt8((($0 ?? 0) * 255).rounded()) }
            }
        }
    }
}

@Suite("Menu bar glyph assets")
struct MenuBarGlyphTests {
    static let variants: [(String, Int)] = MenuBarGlyphRenderer.images.flatMap { image in [(image.name, 1), (image.name, 2)] }

    @Test("write the glyph PNGs",
          .enabled(if: ProcessInfo.processInfo.environment["RIVER_WRITE_GLYPHS"] != nil))
    func writeAssets() throws {
        try FileManager.default.createDirectory(at: MenuBarGlyphRenderer.assetDirectory, withIntermediateDirectories: true)
        for image in MenuBarGlyphRenderer.images {
            for scale in [1, 2] {
                let rendered = try MenuBarGlyphRenderer.render(image.glyph, dark: image.dark, scale: scale)
                let data = try #require(NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]))
                try data.write(to: MenuBarGlyphRenderer.assetDirectory.appendingPathComponent(MenuBarGlyphRenderer.fileName(image.name, scale: scale)))
            }
        }
    }

    // The shipped PNGs are generated, never hand-edited; drift from `StoneMark` means someone
    // changed one without the other. The tolerance absorbs antialiasing differences between
    // macOS versions, not a moved shape or a changed color.
    @Test("the shipped PNGs match the mark", arguments: variants)
    func assetsMatchTheMark(name: String, scale: Int) throws {
        let image = try #require(MenuBarGlyphRenderer.images.first { $0.name == name })
        let url = MenuBarGlyphRenderer.assetDirectory.appendingPathComponent(MenuBarGlyphRenderer.fileName(name, scale: scale))
        let shipped = try #require(NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(shipped.width == Int(Constants.menuBarGlyphSize) * scale)
        #expect(shipped.height == Int(Constants.menuBarGlyphSize) * scale)
        let expected = MenuBarGlyphRenderer.rgba(of: try MenuBarGlyphRenderer.render(image.glyph, dark: image.dark, scale: scale))
        let actual = MenuBarGlyphRenderer.rgba(of: shipped)
        let worst = zip(expected, actual).map { abs(Int($0) - Int($1)) }.max() ?? 255
        #expect(worst <= 8)
    }

    // Only the shipped files `make verify` asserts may sit in the folder `make bundle` copies
    // whole, so a retired glyph cannot ride along in the app.
    @Test("the glyph folder holds exactly the shipped PNGs")
    func folderHoldsShippedFiles() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: MenuBarGlyphRenderer.assetDirectory.path)
        let expected = MenuBarPresentation.Glyph.assetNames.flatMap { [MenuBarGlyphRenderer.fileName($0, scale: 1), MenuBarGlyphRenderer.fileName($0, scale: 2)] }
        #expect(Set(files.filter { $0.hasSuffix(".png") }) == Set(expected))
    }

    // The accent must hold the 3:1 a non-text graphic needs against the menu bar it sits on,
    // measured against an opaque light and dark menu bar (the real one is translucent).
    @Test("the Active accent clears 3:1 on its menu bar", arguments: [(false, 0xE6E6E6), (true, 0x232427)])
    func activeContrast(dark: Bool, menuBar: Int) {
        func luminance(_ color: NSColor) -> Double {
            let srgb = color.usingColorSpace(.sRGB)!
            func channel(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel(srgb.redComponent) + 0.7152 * channel(srgb.greenComponent) + 0.0722 * channel(srgb.blueComponent)
        }
        let bar = NSColor(srgbRed: Double((menuBar >> 16) & 0xFF) / 255, green: Double((menuBar >> 8) & 0xFF) / 255,
                          blue: Double(menuBar & 0xFF) / 255, alpha: 1)
        let accent = luminance(dark ? Palette.accentDark : Palette.accentLight), ground = luminance(bar)
        #expect((max(accent, ground) + 0.05) / (min(accent, ground) + 0.05) >= 3)
    }
}
