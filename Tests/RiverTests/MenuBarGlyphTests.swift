import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import River

/// Renders the menu bar PNGs from `KawaMark` (docs/design/kawa-identity.md): Ready is 川; the
/// other is 川 stepped aside for the dot River draws over it, red while Listening and muted ink
/// while Transcribing. This is the checked-in script: `RIVER_WRITE_GLYPHS=1 swift test --filter MenuBarGlyph` regenerates
/// the assets; the normal suite checks the shipped files still match, so a shape edit without
/// a regeneration fails.
enum MenuBarGlyphRenderer {
    static let assetDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/River/Resources/MenuBarGlyphs")

    static func fileName(_ name: String, scale: Int) -> String {
        scale == 1 ? "\(name).png" : "\(name)@\(scale)x.png"
    }

    // Each PNG's shapes, black with alpha: a template image is read by its alpha only. 川 is
    // centred halfway, as everywhere: 16 pt tall at Ready, 14 pt and left of centre beside the dot.
    static func path(for glyph: MenuBarPresentation.Glyph) -> CGPath {
        let size = Constants.menuBarGlyphSize
        switch glyph {
        case .ready:
            return KawaMark.path(transform: KawaMark.transform(height: Constants.menuBarMarkHeight,
                                                               centredAt: CGPoint(x: size / 2, y: size / 2)))
        case .listening, .transcribing:
            return signedMark
        }
    }

    static let signedMark = KawaMark.path(transform: KawaMark.transform(height: Constants.menuBarSignedMarkHeight,
                                                                        centredAt: Constants.menuBarSignedMarkCentre))

    static func render(_ glyph: MenuBarPresentation.Glyph, scale: Int) throws -> CGImage {
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
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.addPath(path(for: glyph))
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
    // One glyph per shipped PNG, at each scale.
    static let variants: [(MenuBarPresentation.Glyph, Int)] = [MenuBarPresentation.Glyph.ready, .listening].flatMap { glyph in [(glyph, 1), (glyph, 2)] }

    @Test("write the glyph PNGs",
          .enabled(if: ProcessInfo.processInfo.environment["RIVER_WRITE_GLYPHS"] != nil))
    func writeAssets() throws {
        try FileManager.default.createDirectory(at: MenuBarGlyphRenderer.assetDirectory, withIntermediateDirectories: true)
        for (glyph, scale) in Self.variants {
            let rendered = try MenuBarGlyphRenderer.render(glyph, scale: scale)
            let data = try #require(NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]))
            try data.write(to: MenuBarGlyphRenderer.assetDirectory.appendingPathComponent(MenuBarGlyphRenderer.fileName(glyph.assetName, scale: scale)))
        }
    }

    // The shipped PNGs are generated, never hand-edited; drift from the marks means someone
    // changed one without the other. The tolerance absorbs antialiasing differences between
    // macOS versions, not a moved shape or a changed color.
    @Test("the shipped PNGs match the mark", arguments: variants)
    func assetsMatchTheMark(glyph: MenuBarPresentation.Glyph, scale: Int) throws {
        let url = MenuBarGlyphRenderer.assetDirectory.appendingPathComponent(MenuBarGlyphRenderer.fileName(glyph.assetName, scale: scale))
        let shipped = try #require(NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(shipped.width == Int(Constants.menuBarGlyphSize) * scale)
        #expect(shipped.height == Int(Constants.menuBarGlyphSize) * scale)
        let expected = MenuBarGlyphRenderer.rgba(of: try MenuBarGlyphRenderer.render(glyph, scale: scale))
        let actual = MenuBarGlyphRenderer.rgba(of: shipped)
        let worst = zip(expected, actual).map { abs(Int($0) - Int($1)) }.max() ?? 255
        #expect(worst <= 8)
    }

    // The sign is its own mark: it must read apart from the strokes at 1x, so a full pixel of
    // clear bar separates them.
    @Test("the sign never touches the mark, at either scale")
    func signClearsTheMark() throws {
        let gap = 1.0
        for scale in [1, 2] {
            let mark = MenuBarGlyphRenderer.rgba(of: try render(MenuBarGlyphRenderer.signedMark, scale: scale))
            let sign = MenuBarGlyphRenderer.rgba(of: try render(CGPath(ellipseIn: Constants.menuBarSign.insetBy(dx: -gap, dy: -gap),
                                                                       transform: nil), scale: scale))
            let overlap = stride(from: 3, to: mark.count, by: 4).filter { mark[$0] > 0 && sign[$0] > 0 }
            #expect(overlap.isEmpty, "\(overlap.count) pixels at \(scale)x")
        }
    }

    // The red only means the microphone is on. Transcribing keeps the same dot, in muted ink,
    // so it reads as related to recording without being on. Each is drawn in the bar's own
    // appearance, the mark beside it in the bar's text color, as the template icons are.
    @Test("the dot is red while listening and muted ink while transcribing, in each appearance",
          arguments: [(NSAppearance.Name.aqua, 0xB13546 as UInt32), (.darkAqua, 0xDD6871)])
    @MainActor
    func dotIsRedThenMutedInk(appearance: NSAppearance.Name, hex: UInt32) throws {
        let red = NSColor(srgbHex: hex)
        let listening = try draw(muted: false, in: appearance)
        #expect(listening.dot.matches(red))
        #expect(appearance == .darkAqua ? listening.mark.redComponent > 0.8 : listening.mark.redComponent < 0.2)

        // The muted dot is the bar's text color at a reduced strength, not a gray of its own.
        let transcribing = try draw(muted: true, in: appearance)
        var ink = NSColor.labelColor
        try #require(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
            ink = NSColor.labelColor.usingColorSpace(.sRGB) ?? ink
        }
        #expect(abs(transcribing.dot.redComponent - ink.redComponent) < 0.02)
        #expect(abs(transcribing.dot.alphaComponent - ink.alphaComponent * Constants.menuBarMutedDotOpacity) < 0.03)
    }

    // The runtime glyph, drawn at 2x under `appearance`: the dot's centre pixel and
    // the first solid pixel of the mark.
    @MainActor
    private func draw(muted: Bool, in appearance: NSAppearance.Name) throws -> (dot: NSColor, mark: NSColor) {
        let mark = NSImage(cgImage: try MenuBarGlyphRenderer.render(.listening, scale: 2),
                           size: NSSize(width: Constants.menuBarGlyphSize, height: Constants.menuBarGlyphSize))
        let image = MenuBarGlyphImages.withDot(mark, muted: muted)
        #expect(!image.isTemplate)
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 36, bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = NSSize(width: Constants.menuBarGlyphSize, height: Constants.menuBarGlyphSize)
        try #require(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(origin: .zero, size: rep.size))
            NSGraphicsContext.restoreGraphicsState()
        }
        // AppKit's bitmap rows run top down; the dot's box is top-left origin in points.
        let dot = try #require(rep.colorAt(x: Int(Constants.menuBarSign.midX * 2), y: Int(Constants.menuBarSign.midY * 2))?.usingColorSpace(.sRGB))
        let stroke = try #require((0..<36).lazy.flatMap { y in (0..<20).lazy.map { (x: $0, y: y) } }
            .compactMap { rep.colorAt(x: $0.x, y: $0.y)?.usingColorSpace(.sRGB) }.first { $0.alphaComponent > 0.6 })
        return (unpremultiplied(dot), unpremultiplied(stroke))
    }

    // A bitmap's colors come back premultiplied by their alpha.
    private func unpremultiplied(_ c: NSColor) -> NSColor {
        let a = max(c.alphaComponent, 1e-6)
        return NSColor(srgbRed: min(1, c.redComponent / a), green: min(1, c.greenComponent / a), blue: min(1, c.blueComponent / a),
                       alpha: c.alphaComponent)
    }

    private func render(_ path: CGPath, scale: Int) throws -> CGImage {
        let pixels = Int(Constants.menuBarGlyphSize) * scale
        let context = try #require(CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        context.addPath(path)
        context.fillPath()
        return try #require(context.makeImage())
    }

    // Only the shipped files `make verify` asserts may sit in the folder `make bundle` copies
    // whole, so a retired glyph cannot ride along in the app.
    @Test("the glyph folder holds exactly the shipped PNGs")
    func folderHoldsShippedFiles() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: MenuBarGlyphRenderer.assetDirectory.path)
        let expected = MenuBarPresentation.Glyph.assetNames.flatMap { [MenuBarGlyphRenderer.fileName($0, scale: 1), MenuBarGlyphRenderer.fileName($0, scale: 2)] }
        #expect(Set(files.filter { $0.hasSuffix(".png") }) == Set(expected))
    }
}

private extension NSColor {
    func matches(_ other: NSColor) -> Bool {
        abs(redComponent - other.redComponent) < 0.02 && abs(greenComponent - other.greenComponent) < 0.02
            && abs(blueComponent - other.blueComponent) < 0.02
    }
}
