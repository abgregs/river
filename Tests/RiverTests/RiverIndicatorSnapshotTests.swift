import AppKit
import SwiftUI
import Testing
@testable import River

/// Renders the shipped river drawing at held frames to PNGs, for the side-by-side
/// check against the study page (planning 0028) and for PR screenshots. Env-gated like
/// the eval harnesses: the normal suite never writes files.
@Suite("River indicator snapshots", .enabled(if: ProcessInfo.processInfo.environment["RIVER_SNAPSHOT_DIR"] != nil))
@MainActor
struct RiverIndicatorSnapshotTests {
    // Held frames matching the study page's stages: level, strand clock, wall time, crest blend.
    static let frames: [(name: String, level: Double, clock: Double, time: Double, crest: Double)] = [
        ("rest", 0, 0, 0, 0),
        ("level-050", 0.5, 1.3, 0, 0),
        ("level-100", 1, 2.7, 0, 0),
        ("transcribing", 0.4, 0.9, 0.6, 1),
    ]

    @Test("write the capsule at each held frame, 2x, on light and dark appearance")
    func writeSnapshots() throws {
        let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["RIVER_SNAPSHOT_DIR"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for held in Self.frames {
            let frame = RiverIndicatorFrame(level: held.level, clock: held.clock, crestBlend: held.crest, time: held.time)
            for scheme in [ColorScheme.light, .dark] {
                let view = Canvas { context, _ in
                    RiverMarkRenderer.draw(frame, time: held.time, reduceMotion: false, in: &context)
                }
                .frame(width: Constants.riverMarkWidth, height: Constants.riverMarkHeight)
                .padding(.horizontal, Constants.riverCapsuleHorizontalPadding)
                .padding(.vertical, Constants.riverCapsuleVerticalPadding)
                .background { HUDSurface(shape: Capsule()) }
                .padding(Constants.hudShadowMargin)
                .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.92))
                .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try #require(renderer.cgImage)
                let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                try data.write(to: directory.appendingPathComponent("river-\(held.name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }
}
