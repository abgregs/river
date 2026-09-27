import AppKit
import Combine
import SwiftUI
import Testing
@testable import River

/// Renders the shipped pixel-mark drawing at held frames to PNGs, for the side-by-side
/// check against the study page (planning 0029) and for PR screenshots. Env-gated like
/// the eval harnesses: the normal suite never writes files.
@Suite("River indicator snapshots", .enabled(if: ProcessInfo.processInfo.environment["RIVER_SNAPSHOT_DIR"] != nil))
@MainActor
struct RiverIndicatorSnapshotTests {
    // Held frames matching the study page's stages, run through the real engine with a fixed
    // seed so the meter's reading is the same on every run.
    static func frames() -> [(name: String, frame: PixelMarkFrame, increaseContrast: Bool)] {
        let start = 1_000.0
        let speaking: (Double) -> Double = { inputLevel(decibels: speechDecibels + 5 * sin($0 * 9)) }
        let quiet: (Double) -> Double = { inputLevel(decibels: quietSpeechDecibels + 3 * sin($0 * 9)) }
        let rest = PixelMarkFrame(seed: 11).running(.rest, from: start, for: 0.3).frame
        let preparing = PixelMarkFrame(seed: 11).running(.preparing, from: start, for: 1.2).frame
        let silence = PixelMarkFrame(seed: 11).running(.listening, from: start, for: 1.5).frame
        let quietTalking = PixelMarkFrame(seed: 11).running(.listening, from: start, for: 2, level: quiet).frame
        let (listening, end) = PixelMarkFrame(seed: 11).running(.listening, from: start, for: 2, level: speaking)
        let transcribing = listening.running(.transcribing, from: end, for: Constants.pixelReturnSeconds + 0.6).frame
        let (reduced, reducedEnd) = PixelMarkFrame(seed: 11).running(.listening, from: start, for: 1, reduceMotion: true, level: speaking)
        let reducedTranscribing = reduced.running(.transcribing, from: reducedEnd, for: 1, reduceMotion: true).frame
        return [
            ("rest", rest, false),
            ("preparing", preparing, false),
            ("listening-silence", silence, false),
            ("listening-silence-contrast", silence, true),
            ("listening-quiet", quietTalking, false),
            ("listening-speaking", listening, false),
            ("transcribing", transcribing, false),
            ("transcribing-reduce-motion", reducedTranscribing, false),
        ]
    }

    @Test("write the mark's panel at each held frame, 2x, on light and dark appearance")
    func writeSnapshots() throws {
        let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["RIVER_SNAPSHOT_DIR"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for held in Self.frames() {
            for scheme in [ColorScheme.light, .dark] {
                let view = Canvas { context, _ in
                    PixelMarkRenderer.draw(held.frame, increaseContrast: held.increaseContrast, in: &context)
                }
                .frame(width: Constants.pixelMarkSize, height: Constants.pixelMarkSize)
                .padding(.horizontal, Constants.indicatorPanelHorizontalPadding)
                .padding(.vertical, Constants.indicatorPanelVerticalPadding)
                .background {
                    HUDSurface(shape: RoundedRectangle(cornerRadius: Constants.indicatorPanelCornerRadius, style: .continuous))
                }
                .padding(Constants.hudShadowMargin)
                .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.92))
                .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try #require(renderer.cgImage)
                let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                try data.write(to: directory.appendingPathComponent("mark-\(held.name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }

    // The whole panel content from a real `AppState`, for the stacking and message checks.
    @Test("write the full indicator with its message rectangle, 2x, on light and dark appearance")
    func writeStackSnapshots() throws {
        let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["RIVER_SNAPSHOT_DIR"]))
        // The suite's tests run in parallel, so each creates the directory it writes to.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        struct Failure: Error {}
        let scenarios: [(name: String, configure: (AppState) -> Void)] = [
            ("recording-notice", { state in
                state.apply(modelLoadState: .ready)
                state.apply(.recording)
                state.apply(notice: "Activation key changed. Tap Right Command to stop this recording.")
            }),
            ("processing-toast", { state in
                state.apply(modelLoadState: .ready)
                state.apply(.recording)
                state.apply(RiverError.textInsertion(underlying: Failure()))
                state.apply(.processing)
            }),
            ("idle-toast", { state in
                state.apply(modelLoadState: .ready)
                state.apply(RiverError.transcription(underlying: Failure()))
            }),
            ("idle-loading", { state in state.apply(modelLoadState: .loading) }),
        ]
        for scenario in scenarios {
            let appState = AppState(scheduleToastDismiss: { _, _ in AnyCancellable {} })
            scenario.configure(appState)
            for scheme in [ColorScheme.light, .dark] {
                let view = RiverIndicatorView(appState: appState)
                    .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.92))
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try #require(renderer.cgImage)
                let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                try data.write(to: directory.appendingPathComponent("stack-\(scenario.name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }
}
