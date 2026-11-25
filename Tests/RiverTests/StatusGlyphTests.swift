import AppKit
import SwiftUI
import Testing
@testable import River

/// The status row's own glyphs sit centred in their tile. App switched's sheet once ran from 1.75
/// to 13.75 on the 14 pt grid, 0.75 pt low, which read as a mistake beside the centred ring
/// (maintainer, 2026-11-24).
@Suite("Status glyphs")
@MainActor
struct StatusGlyphTests {
    // The drawing's ink bounds on the 14 pt grid, from a 16x render: every pixel at 4 % alpha or more.
    static func inkBounds(_ draw: @escaping (inout GraphicsContext, CGSize) -> Void) throws -> CGRect {
        let scale = 16.0
        let renderer = ImageRenderer(content: Canvas { context, size in draw(&context, size) }
            .frame(width: StatusRing.grid * scale, height: StatusRing.grid * scale))
        renderer.scale = 1
        let rep = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var box = CGRect.null
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) >= 0.04 {
                box = box.union(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return CGRect(x: box.minX / scale, y: box.minY / scale, width: box.width / scale, height: box.height / scale)
    }

    @Test("the held sheet and the lock centre their ink in the tile", arguments: ["held", "lock"])
    func glyphIsCentred(name: String) throws {
        let bounds = try Self.inkBounds { context, size in
            if name == "held" {
                HeldSheetRenderer.draw(in: &context, size: size, ink: .black)
            } else {
                LockRenderer.draw(in: &context, size: size, ink: .black)
            }
        }
        #expect(abs(bounds.midX - StatusRing.grid / 2) < 0.1, "\(name) is off centre across: \(bounds)")
        #expect(abs(bounds.midY - StatusRing.grid / 2) < 0.1, "\(name) is off centre down: \(bounds)")
    }
}
