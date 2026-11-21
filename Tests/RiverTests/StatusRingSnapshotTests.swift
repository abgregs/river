import AppKit
import SwiftUI
import Testing
@testable import River

/// Renders the status ring at held moments to PNGs, for the side-by-side check against the
/// preparing status study, round ten (docs/design/studies/preparing/preparing-status-r10.html, its
/// ring states and filmstrips at the same times), and for PR screenshots. Env-gated like the
/// other snapshot harnesses: the normal suite never writes files.
@Suite("Status ring snapshots", .enabled(if: ProcessInfo.processInfo.environment["RIVER_SNAPSHOT_DIR"] != nil))
@MainActor
struct StatusRingSnapshotTests {
    struct Held {
        let name: String
        let events: StatusRingEvents
        let time: Double
        var reduceMotion = false
    }

    static let frames: [Held] = {
        let downloading = StatusRingEvents(appearing: .downloading, fraction: 0.62)
        var closing = StatusRingEvents(appearing: .downloading, fraction: 0.98)
        closing.preparing = 1
        let preparing = StatusRingEvents(appearing: .preparing, fraction: nil)
        var ready = preparing
        ready.ready = 2
        var failing = downloading
        failing.failed = 1
        var failingAfter = preparing
        failingAfter.failed = 1
        return [
            Held(name: "downloading", events: downloading, time: 0),
            Held(name: "downloading-breath", events: downloading, time: 1.4),
            Held(name: "hand-off", events: closing, time: 1.3),
            Held(name: "preparing", events: preparing, time: 1.6),
            Held(name: "ready-check-revealing", events: ready, time: 2.35),
            Held(name: "ready", events: ready, time: 3),
            Held(name: "failing-akane", events: failing, time: 1.6),
            Held(name: "failing-sign-revealing", events: failing, time: 2.05),
            Held(name: "failed-download", events: failing, time: 2.5),
            Held(name: "failed-after-download", events: failingAfter, time: 2.5),
            Held(name: "reduce-motion-preparing", events: preparing, time: 1.4, reduceMotion: true),
        ]
    }()

    @Test("write the ring at each held moment, on the mark's tile at 4x, in light and dark appearance")
    func writeSnapshots() throws {
        let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["RIVER_SNAPSHOT_DIR"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for held in Self.frames {
            let frame = StatusRing.frame(at: held.time, events: held.events, reduceMotion: held.reduceMotion)
            for scheme in [ColorScheme.light, .dark] {
                let colors = Palette.HUD.for(scheme)
                // The tile the ring sits on beside the panel: 26 pt, the glyph inset 6 pt.
                let view = StatusRingGlyph(frame: frame)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(nsColor: colors.tint)))
                    .padding(8)
                    .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.92))
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 4
                let image = try #require(renderer.cgImage)
                let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                try data.write(to: directory.appendingPathComponent("ring-\(held.name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }
}
