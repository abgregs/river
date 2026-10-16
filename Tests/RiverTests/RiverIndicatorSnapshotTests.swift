import AppKit
import Combine
import SwiftUI
import Testing
@testable import River

/// Renders the shipped stones-mark drawing at held frames to PNGs, for the side-by-side
/// check against the study page (docs/design/studies/stones-motion.html) and for PR
/// screenshots. Env-gated like the eval harnesses: the normal suite never writes files.
@Suite("River indicator snapshots", .enabled(if: ProcessInfo.processInfo.environment["RIVER_SNAPSHOT_DIR"] != nil))
@MainActor
struct RiverIndicatorSnapshotTests {
    // Held frames matching the study page's stages, run through the real engine with a fixed
    // seed so the bars' reading is the same on every run.
    static func frames() -> [(name: String, frame: StoneMarkFrame)] {
        let start = 1_000.0
        let speaking: (Double) -> Double = { inputLevel(decibels: speechDecibels + 5 * sin($0 * 9)) }
        let quiet: (Double) -> Double = { inputLevel(decibels: quietSpeechDecibels + 3 * sin($0 * 9)) }
        let rest = StoneMarkFrame(seed: 11).running(.rest, from: start, for: 0.3).frame
        let preparing = StoneMarkFrame(seed: 11).running(.preparing, from: start, for: 1.2).frame
        let morphing = StoneMarkFrame(seed: 11).running(.listening, from: start, for: Constants.markHoldSeconds + 0.12, fps: 120).frame
        let silence = StoneMarkFrame(seed: 11).running(.listening, from: start, for: 1.5).frame
        let quietTalking = StoneMarkFrame(seed: 11).running(.listening, from: start, for: 2, level: quiet).frame
        let (listening, end) = StoneMarkFrame(seed: 11).running(.listening, from: start, for: 2, level: speaking)
        let transcribing = listening.running(.transcribing, from: end, for: 0.8).frame
        let reduced = StoneMarkFrame(seed: 11).running(.listening, from: start, for: 2, reduceMotion: true, level: speaking).frame
        return [
            ("rest", rest),
            ("preparing", preparing),
            ("morphing", morphing),
            ("listening-silence", silence),
            ("listening-quiet", quietTalking),
            ("listening-speaking", listening),
            ("transcribing", transcribing),
            ("listening-reduce-motion", reduced),
        ]
    }

    @Test("write the mark's panel at each held frame, 2x, on light and dark appearance")
    func writeSnapshots() throws {
        let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["RIVER_SNAPSHOT_DIR"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for held in Self.frames() {
            for scheme in [ColorScheme.light, .dark] {
                let view = Canvas { context, size in
                    StoneMarkRenderer.draw(held.frame, in: &context, size: size)
                }
                .frame(width: Constants.indicatorMarkSize, height: Constants.indicatorMarkSize)
                .padding(.horizontal, Constants.indicatorPanelHorizontalPadding)
                .padding(.vertical, Constants.indicatorPanelVerticalPadding)
                .background {
                    HUDSurface(cornerRadius: Constants.indicatorPanelCornerRadius)
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
            ("recording-transcript", { state in
                state.apply(modelLoadState: .ready)
                state.apply(.recording)
                state.apply(liveTranscript: "So the idea is that the transcript streams in here while I keep talking.")
            }),
            ("recording-transcript-notice", { state in
                state.apply(modelLoadState: .ready)
                state.apply(.recording)
                state.apply(liveTranscript: "So the idea is that the transcript streams in here while I keep talking.")
                state.apply(notice: "Activation key changed. Tap Right Command to stop this recording.")
            }),
            ("processing-transcript-toast", { state in
                state.apply(modelLoadState: .ready)
                state.apply(.recording)
                state.apply(liveTranscript: "So the idea is that the transcript streams in here while I keep talking.")
                state.apply(.processing)
                state.apply(RiverError.transcription(underlying: Failure()))
            }),
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
