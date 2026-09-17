import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import River

/// Renders the slat glyph's template PNGs from the geometry in `Constants` (planning
/// 0028). This is the checked-in script: `RIVER_WRITE_GLYPHS=1 swift test --filter
/// MenuBarGlyph` regenerates the assets; the normal suite checks the shipped files
/// still match, so a geometry edit without a regeneration fails.
enum MenuBarGlyphRenderer {
    static let assetDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/River/Resources/MenuBarGlyphs")

    static func fileName(_ glyph: MenuBarPresentation.Glyph, scale: Int) -> String {
        scale == 1 ? "\(glyph.rawValue).png" : "\(glyph.rawValue)@\(scale)x.png"
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
        // Top-left origin in points, matching the study page's 16-unit box.
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        context.setShouldAntialias(true)
        let centers = scale == 1 ? Constants.menuBarGlyphRowCenters1x : Constants.menuBarGlyphRowCenters2x
        for (row, inset) in Constants.menuBarGlyphRowInsets.enumerated() {
            let y = centers[row]
            let start = inset, end = size - inset
            switch glyph {
            case .ready, .listening:
                let isReady = glyph == .ready
                let ink = isReady && row != 2 ? Constants.menuBarGlyphReadySideInk : 1
                context.setStrokeColor(CGColor(gray: 0, alpha: ink))
                context.setLineWidth(isReady ? Constants.menuBarGlyphReadyStroke : Constants.menuBarGlyphListeningStroke)
                context.setLineCap(.round)
                context.move(to: CGPoint(x: start, y: y))
                context.addLine(to: CGPoint(x: end, y: y))
                context.strokePath()
            case .transcribing:
                // Real circles whose first and last sit on the slat's endpoints, so the dotted
                // outline is the solid outline (identity-studies working rule 12).
                let count = Constants.menuBarGlyphDotCounts[row]
                let radius = Constants.menuBarGlyphDotRadius
                context.setFillColor(CGColor(gray: 0, alpha: 1))
                for dot in 0..<count {
                    let even = start + (end - start) * Double(dot) / Double(count - 1)
                    // At 2x the in-between dots snap to device pixels so none renders as two
                    // half-lit columns; the endpoints already sit on the grid and never move.
                    let x = scale == 2 ? (even * 2).rounded() / 2 : even
                    context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius))
                }
            }
        }
        guard let image = context.makeImage() else { throw ContextUnavailable() }
        return image
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
    // antialiasing differences between macOS versions, not a moved or resized slat.
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

    // Crisp means the slat body covers whole device-pixel rows: at 2x a 1.1 pt stroke on a
    // pixel boundary fills two full rows; at 1x a 1.1 px stroke on a pixel center fills one.
    // A dot straddling two pixel columns reads as a split, blurred dot at menu bar size.
    @Test("every transcribing dot at 2x is centered on a device-pixel boundary")
    func dotsAreCrispAt2x() throws {
        let alpha = MenuBarGlyphRenderer.alpha(of: try MenuBarGlyphRenderer.render(.transcribing, scale: 2))
        let side = Int(Constants.menuBarGlyphSize) * 2
        let middleRow = Int(Constants.menuBarGlyphRowCenters2x[2] * 2)
        let lit = (0..<side).map { alpha[middleRow * side + $0] }
        // Each dot's two center columns are equally lit, so no dot leans into a half column.
        let peaks = (1..<side).filter { lit[$0] > 100 && lit[$0] == lit[$0 - 1] }
        #expect(peaks.count == Constants.menuBarGlyphDotCounts[2])
    }

    @Test("slat bodies fill whole device-pixel rows at 1x and 2x", arguments: [1, 2])
    func slatsAreCrisp(scale: Int) throws {
        let alpha = MenuBarGlyphRenderer.alpha(of: try MenuBarGlyphRenderer.render(.listening, scale: scale))
        let side = Int(Constants.menuBarGlyphSize) * scale
        let middleX = side / 2
        let centers = scale == 1 ? Constants.menuBarGlyphRowCenters1x : Constants.menuBarGlyphRowCenters2x
        for center in centers {
            let fullRows = (0..<side).filter { alpha[$0 * side + middleX] >= 250 }
            let expectedRows = scale == 1
                ? [Int(center * 1)]
                : [Int(center * 2) - 1, Int(center * 2)]
            #expect(expectedRows.allSatisfy(fullRows.contains))
        }
    }
}
