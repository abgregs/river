import AppKit
import SwiftUI
import Testing
@testable import River

/// The status row's own glyph sits centred in its tile. A glyph 0.75 pt low read as a mistake
/// beside the centred ring (maintainer, 2026-11-24).
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

    @Test("the lock centres its ink in the tile")
    func lockIsCentred() throws {
        let bounds = try Self.inkBounds { context, size in
            LockRenderer.draw(in: &context, size: size, ink: .black)
        }
        #expect(abs(bounds.midX - StatusRing.grid / 2) < 0.1, "the lock is off centre across: \(bounds)")
        #expect(abs(bounds.midY - StatusRing.grid / 2) < 0.1, "the lock is off centre down: \(bounds)")
    }
}
