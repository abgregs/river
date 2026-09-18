import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import River

/// Renders the app icon — the slat mark in ink on a charcoal squircle — from the same
/// geometry the menu bar glyph uses. The checked-in script:
/// `RIVER_WRITE_ICON=1 swift test --filter AppIcon` regenerates `River.icns`; the normal
/// suite checks the shipped file still carries every size macOS asks for.
enum AppIconRenderer {
    static let resourceDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/River/Resources")

    // The sizes an .icns carries, each at 1x and 2x.
    static let pointSizes = [16, 32, 128, 256, 512]

    static func render(pixels: Int) throws -> CGImage {
        struct ContextUnavailable: Error {}
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ContextUnavailable() }
        let scale = Double(pixels) / Constants.appIconCanvas
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        context.setShouldAntialias(true)

        // SwiftUI's continuous corner is Apple's squircle; a plain rounded rect is not.
        let inset = Constants.appIconSquircleInset
        let side = Constants.appIconCanvas - 2 * inset
        let squircle = RoundedRectangle(cornerRadius: Constants.appIconCornerRadius, style: .continuous)
            .path(in: CGRect(x: inset, y: inset, width: side, height: side))
        context.addPath(squircle.cgPath)
        context.setFillColor(Palette.charcoal.cgColor)
        context.fillPath()

        // The mark is drawn at full ink on every slat: the icon carries no cycle state.
        let markWidth = side * Constants.appIconMarkFraction
        let unit = markWidth / Constants.menuBarGlyphSize
        context.saveGState()
        context.translateBy(x: (Constants.appIconCanvas - markWidth) / 2, y: (Constants.appIconCanvas - markWidth) / 2)
        MenuBarGlyphRenderer.drawSlats(.listening, scale: 2, unit: unit, color: Palette.ink.cgColor, in: context)
        context.restoreGState()

        guard let image = context.makeImage() else { throw ContextUnavailable() }
        return image
    }
}

@Suite("App icon")
struct AppIconTests {
    @Test("write River.icns",
          .enabled(if: ProcessInfo.processInfo.environment["RIVER_WRITE_ICON"] != nil))
    func writeIcon() throws {
        let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("River.iconset")
        try? FileManager.default.removeItem(at: iconset)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for points in AppIconRenderer.pointSizes {
            for scale in [1, 2] {
                let image = try AppIconRenderer.render(pixels: points * scale)
                let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                let suffix = scale == 1 ? "" : "@2x"
                try data.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
            }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = [
            "-c", "icns", iconset.path,
            "-o", AppIconRenderer.resourceDirectory.appendingPathComponent(Constants.appIconFileName).path,
        ]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    // A missing size makes macOS scale a neighbor, which is what a blurry Finder icon
    // looks like. The shipped file must carry every representation.
    @Test("the shipped icon carries every size at 1x and 2x")
    func shippedIconHasEverySize() throws {
        let url = AppIconRenderer.resourceDirectory.appendingPathComponent(Constants.appIconFileName)
        let image = try #require(NSImage(contentsOf: url))
        let widths = Set(image.representations.map(\.pixelsWide))
        for points in AppIconRenderer.pointSizes {
            #expect(widths.contains(points))
            #expect(widths.contains(points * 2))
        }
    }

    // The mark must stay well inside the squircle: ink touching the corner radius reads
    // as a crop, and Apple's grid leaves the outer band empty.
    @Test("the mark sits inside the squircle with margin on every side")
    func markFitsInsideSquircle() throws {
        let pixels = 256
        let image = try AppIconRenderer.render(pixels: pixels)
        let rep = NSBitmapImageRep(cgImage: image)
        let inkColumns = (0..<pixels).filter { x in
            (0..<pixels).contains { y in (rep.colorAt(x: x, y: y)?.brightnessComponent ?? 0) > 0.5 }
        }
        let squircleStart = Constants.appIconSquircleInset / Constants.appIconCanvas * Double(pixels)
        let squircleEnd = Double(pixels) - squircleStart
        let first = try #require(inkColumns.first), last = try #require(inkColumns.last)
        #expect(Double(first) > squircleStart + 8)
        #expect(Double(last) < squircleEnd - 8)
        // Centered: the ink's margins match on both sides.
        #expect(abs((Double(first) - squircleStart) - (squircleEnd - Double(last))) < 2)
    }
}
