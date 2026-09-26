import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import River

/// Renders the pixel r's template PNGs from `PixelMark` and the geometry in `Constants`
/// (planning 0029). This is the checked-in script: `RIVER_WRITE_GLYPHS=1 swift test --filter
/// MenuBarGlyph` regenerates the assets; the normal suite checks the shipped files still
/// match, so a geometry edit without a regeneration fails.
enum MenuBarGlyphRenderer {
    static let assetDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/River/Resources/MenuBarGlyphs")

    static func fileName(_ glyph: MenuBarPresentation.Glyph, scale: Int) -> String {
        scale == 1 ? "\(glyph.rawValue).png" : "\(glyph.rawValue)@\(scale)x.png"
    }

    static func geometry(scale: Int) -> (cell: Double, gap: Double) {
        scale == 1
            ? (Constants.menuBarGlyphCell1x, Constants.menuBarGlyphGap1x)
            : (Constants.menuBarGlyphCell2x, Constants.menuBarGlyphGap2x)
    }

    // Black ink with alpha on a clear ground: a template image is read by its alpha only.
    static func render(_ glyph: MenuBarPresentation.Glyph, scale: Int) throws -> CGImage {
        let size = Constants.menuBarGlyphSize
        let pixels = Int(size) * scale
        struct ContextUnavailable: Error {}
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ContextUnavailable() }
        // Top-left origin in points, matching the map's rows.
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        context.setShouldAntialias(true)
        let (cell, gap) = geometry(scale: scale)
        drawPixelMark(PixelMark.staticCells(for: glyph), cell: cell, gap: gap, color: CGColor(gray: 0, alpha: 1), in: context)
        guard let image = context.makeImage() else { throw ContextUnavailable() }
        return image
    }

    // The mark itself, one rounded square per cell. Shared with the app icon so both
    // surfaces are one drawing (identity-studies rule 8).
    static func drawPixelMark(_ cells: [PixelMark.StaticCell], cell: Double, gap: Double, color: CGColor, in context: CGContext) {
        let radius = PixelMark.cornerRadius(cell: cell)
        for pixel in cells {
            let rect = PixelMark.cellRect(x: Double(pixel.x), y: Double(pixel.y), cell: cell, gap: gap)
            context.setFillColor(color.copy(alpha: pixel.ink) ?? color)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
        }
    }

    static func alpha(of image: CGImage) -> [UInt8] {
        let rep = NSBitmapImageRep(cgImage: image)
        return (0..<rep.pixelsHigh).flatMap { y in
            (0..<rep.pixelsWide).map { x in UInt8(((rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) * 255).rounded()) }
        }
    }
}

@Suite("Menu bar glyph assets")
struct MenuBarGlyphTests {
    static let variants: [(MenuBarPresentation.Glyph, Int)] =
        MenuBarPresentation.Glyph.allCases.flatMap { glyph in [(glyph, 1), (glyph, 2)] }

    @Test("write the template PNGs",
          .enabled(if: ProcessInfo.processInfo.environment["RIVER_WRITE_GLYPHS"] != nil))
    func writeAssets() throws {
        try FileManager.default.createDirectory(at: MenuBarGlyphRenderer.assetDirectory, withIntermediateDirectories: true)
        for (glyph, scale) in Self.variants {
            let image = try MenuBarGlyphRenderer.render(glyph, scale: scale)
            let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try data.write(to: MenuBarGlyphRenderer.assetDirectory.appendingPathComponent(MenuBarGlyphRenderer.fileName(glyph, scale: scale)))
        }
    }

    // The shipped PNGs are generated, never hand-edited; drift from the geometry in
    // `Constants` means someone changed one without the other. The tolerance absorbs
    // antialiasing differences between macOS versions, not a moved or resized cell.
    @Test("the shipped PNGs match the geometry in Constants", arguments: variants)
    func assetsMatchGeometry(glyph: MenuBarPresentation.Glyph, scale: Int) throws {
        let url = MenuBarGlyphRenderer.assetDirectory.appendingPathComponent(MenuBarGlyphRenderer.fileName(glyph, scale: scale))
        let shipped = try #require(NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(shipped.width == Int(Constants.menuBarGlyphSize) * scale)
        #expect(shipped.height == Int(Constants.menuBarGlyphSize) * scale)
        let expected = MenuBarGlyphRenderer.alpha(of: try MenuBarGlyphRenderer.render(glyph, scale: scale))
        let actual = MenuBarGlyphRenderer.alpha(of: shipped)
        let worst = zip(expected, actual).map { abs(Int($0) - Int($1)) }.max() ?? 255
        #expect(worst <= 8)
    }

    // A cell edge between two device pixels renders as a half-lit column, which reads as a
    // blurred mark at menu bar size; the grid's origin and pitch keep every edge whole.
    @Test("every cell edge lands on a device pixel", arguments: [1, 2])
    func cellsAreCrisp(scale: Int) {
        let (cell, gap) = MenuBarGlyphRenderer.geometry(scale: scale)
        for glyph in MenuBarPresentation.Glyph.allCases {
            for pixel in PixelMark.staticCells(for: glyph) {
                let rect = PixelMark.cellRect(x: Double(pixel.x), y: Double(pixel.y), cell: cell, gap: gap)
                for edge in [rect.minX, rect.maxX, rect.minY, rect.maxY] {
                    let devicePixels = edge * Double(scale)
                    #expect(devicePixels == devicePixels.rounded())
                }
            }
        }
    }

    @Test("the mark fits the 18 pt box at both scales", arguments: [1, 2])
    func markFitsTheBox(scale: Int) {
        let (cell, gap) = MenuBarGlyphRenderer.geometry(scale: scale)
        #expect(PixelMark.extent(cell: cell, gap: gap) <= Constants.menuBarGlyphSize)
    }
}
