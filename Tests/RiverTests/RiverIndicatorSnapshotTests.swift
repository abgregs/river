import AppKit
import Combine
import SwiftUI
import Testing
@testable import River

/// Renders the shipped kawa drawing at held frames to PNGs, for the side-by-side check against
/// the study pages (docs/design/studies/kawa/kawa-studies-r1.html and kawa-glass-r1.html, their
/// filmstrips at the same times) and for PR screenshots. Env-gated like the eval harnesses: the normal suite never
/// writes files. Glass needs its shader, which the harness compiles first (Xcode's Metal
/// compiler); without it, the held frames are skipped with a message.
@Suite("River indicator snapshots", .enabled(if: ProcessInfo.processInfo.environment["RIVER_SNAPSHOT_DIR"] != nil))
@MainActor
struct RiverIndicatorSnapshotTests {
    struct Held {
        let name: String
        let events: KawaIndicatorEvents
        let voice: (Double) -> Double
        let time: Double
        var reduceMotion = false
    }

    // The study's scripts: a dictation; three phrases held soft, normal and raised; a phrase
    // then quiet, for the frost's return; a dead microphone; and preparing.
    static let steps: (Double) -> Double = {
        let soft = sentence(1.3, 2.8, pauseAt: 9, pauseLength: 0, seed: 31, low: 0.26, span: 0.08)
        let normal = sentence(3.15, 4.65, pauseAt: 9, pauseLength: 0, seed: 37, low: 0.58, span: 0.1)
        let raised = sentence(5.0, 6.5, pauseAt: 9, pauseLength: 0, seed: 41, low: 0.88, span: 0.1)
        return { max(soft($0), normal($0), raised($0)) }
    }()
    static let stepsEvents = KawaIndicatorEvents(press: 0.3, audio: 0.32, release: 6.8, typed: 7.5)
    static let stop = sentence(1.3, 3.3, pauseAt: 9, pauseLength: 0, seed: 23, low: 0.5, span: 0.14)
    // When the phrase's last word ends: the last step the voice is above 0.
    static let stopLast = stride(from: 4.0, to: 1.3, by: -1 / Constants.kawaEngineStepsPerSecond).first { stop($0) > 0 }!
    static let stopEvents = KawaIndicatorEvents(press: 0.3, audio: 0.32, release: stopLast + 2.6, typed: stopLast + 3.2)
    static let dead = KawaIndicatorEvents(press: 0.3, release: 4.2, typed: 4.45)
    static let preparing = KawaIndicatorEvents(press: 0.3, release: 2.6, typed: 2.6)

    // The study's Glass filmstrip, then the soft, normal and loud steps and the edge cases.
    static let frames: [Held] = {
        let film: [(String, Double)] = [("press", 0.38), ("muted", 0.6), ("forming", 0.88), ("idle", 1.3), ("speaking", 1.62),
                                        ("louder", 2.45), ("pause", 4.1), ("released", 6.3), ("lifting", 6.45), ("typed", 7.32)]
        return film.map { Held(name: $0.0, events: dictation, voice: dictationVoice, time: $0.1) } + [
            Held(name: "soft", events: stepsEvents, voice: steps, time: 2.3),
            Held(name: "normal", events: stepsEvents, voice: steps, time: 4.1),
            Held(name: "loud", events: stepsEvents, voice: steps, time: 5.9),
            // The Glass study's film: quiet 0.4, 1.2 and 2.2 s after the last word.
            Held(name: "quiet", events: stopEvents, voice: stop, time: stopLast + 0.4),
            Held(name: "returning", events: stopEvents, voice: stop, time: stopLast + 1.2),
            Held(name: "returned", events: stopEvents, voice: stop, time: stopLast + 2.2),
            Held(name: "dead-microphone", events: dead, voice: dictationVoice, time: 2.4),
            Held(name: "preparing", events: preparing, voice: { _ in 0 }, time: 1.2),
            Held(name: "reduce-motion", events: dictation, voice: dictationVoice, time: 2.45, reduceMotion: true),
        ]
    }()

    @Test("write the mark's panel at each held frame, 2x, on light and dark appearance")
    func writeSnapshots() throws {
        let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["RIVER_SNAPSHOT_DIR"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let glass = try Self.compileGlassLibrary(into: directory) else {
            print("Skipping Glass snapshots: the shader did not compile (is Xcode's Metal compiler selected?)")
            return
        }
        for held in Self.frames {
            // Fed the way the app feeds the panel: the microphone's peak reading every publish
            // interval, through the panel's own voice, one frame at a time.
            let voice = KawaIndicatorVoice(makeEngine: { KawaIndicatorEngine(seed: 0) })
            let id = UUID()
            var engine = KawaIndicatorEngine(seed: 0)
            for frame in 0...Int(held.time * Self.framesPerSecond) {
                engine = voice.engine(for: id, events: held.events, at: Double(frame) / Self.framesPerSecond,
                                      inputLevel: Self.reading(held.voice, at: Double(frame) / Self.framesPerSecond),
                                      reduceMotion: held.reduceMotion)
            }
            engine = voice.engine(for: id, events: held.events, at: held.time, inputLevel: Self.reading(held.voice, at: held.time),
                                  reduceMotion: held.reduceMotion)
            let channels = KawaIndicatorTimeline.channels(at: held.time, events: held.events, reduceMotion: held.reduceMotion)
            for scheme in [ColorScheme.light, .dark] {
                let view = KawaMarkPanelFace(channels: channels, time: held.time, reduceMotion: held.reduceMotion,
                                             engine: engine, glassLibrary: glass)
                    .padding(Constants.hudShadowMargin)
                    .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.92))
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try #require(renderer.cgImage)
                let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                try data.write(to: directory.appendingPathComponent(
                    "glass-\(held.name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }

    static let framesPerSecond = 60.0

    // The `inputLevel` the microphone would have published by `t`: the loudest of the study's
    // voice over the publish interval that ended last, as the capture's peak hold reports it.
    static func reading(_ voice: (Double) -> Double, at t: Double) -> Double {
        let interval = Constants.inputLevelPublishInterval
        let end = (t / interval).rounded(.down) * interval
        let peak = stride(from: max(0, end - interval), through: end, by: 1 / Constants.kawaEngineStepsPerSecond).map(voice).max() ?? 0
        guard peak > 0 else { return 0 }
        // The inverse of `KawaIndicatorEngine.loudness(level:)`.
        let floor = Constants.markMeterFloorDecibels, ceiling = Constants.markMeterCeilingDecibels
        return inputLevel(decibels: floor + pow(peak, 1 / Constants.markMeterCurve) * (ceiling - floor))
    }

    // The Makefile's two steps, into the snapshot directory.
    static func compileGlassLibrary(into directory: URL) throws -> ShaderLibrary? {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/River/Shaders/KawaGlass.metal").standardizedFileURL
        let air = directory.appendingPathComponent("KawaGlass.air"), library = directory.appendingPathComponent("KawaGlass.metallib")
        for arguments in [["-sdk", "macosx", "metal", "-c", source.path, "-o", air.path],
                          ["-sdk", "macosx", "metallib", air.path, "-o", library.path]] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = arguments
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
        }
        return GlassRenderer.load(library)
    }

    // The frost forming over the strokes must read as one move: the strokes' clarity, their CIE L*
    // distance from the ground beside them, never peaks on the way in or on the way out. The shader
    // once aimed the ink at its cleared strength until the frost had formed, so the strokes
    // brightened under the thin veil and dimmed as it thickened: about 6 L* in Light mode and 10 in
    // Dark, seen on device as a pulse (2026-11-04). Silent, so no ripple moves the strokes.
    @Test("the strokes' clarity never peaks as the frost forms or lifts, on light and dark appearance",
          arguments: [ColorScheme.light, .dark])
    func frostFormsInOneMove(scheme: ColorScheme) throws {
        let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["RIVER_SNAPSHOT_DIR"]))
            .appendingPathComponent("clarity-\(scheme == .dark ? "dark" : "light")")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let glass = try Self.compileGlassLibrary(into: directory) else {
            print("Skipping the clarity check: the shader did not compile (is Xcode's Metal compiler selected?)")
            return
        }
        func render(_ view: some View) throws -> NSBitmapImageRep {
            let renderer = ImageRenderer(content: view.frame(width: Constants.indicatorPanelWidth, height: Constants.indicatorPanelHeight))
            renderer.scale = 2
            return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        }
        func lightness(_ color: NSColor) -> Double {
            let c = color.usingColorSpace(.sRGB)!
            func linear(_ v: CGFloat) -> Double { let v = Double(v); return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            let y = 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
            return y > 0.008856 ? 116 * pow(y, 1.0 / 3) - 16 : 903.3 * y
        }
        // The pixels inside the strokes and well clear of them, from the strokes drawn solid.
        let mask = try render(Canvas { context, _ in context.fill(KawaMutedStrokes.path, with: .color(.black)) }.background(Color.white))
        var strokes: [(Int, Int)] = [], ground: [(Int, Int)] = []
        for y in 0..<mask.pixelsHigh {
            for x in 0..<mask.pixelsWide {
                let brightness = mask.colorAt(x: x, y: y)!.brightnessComponent
                if brightness < 0.02 { strokes.append((x, y)) } else if brightness > 0.999 { ground.append((x, y)) }
            }
        }
        let events = KawaIndicatorEvents(press: 0.3, audio: 0.32, release: 2.5, typed: 3.2)
        func clarity(at t: Double) throws -> Double {
            let channels = KawaIndicatorTimeline.channels(at: t, events: events, reduceMotion: false)
            let frame = try render(KawaMarkFrame(channels: channels, time: t, reduceMotion: false, engine: KawaIndicatorEngine(seed: 0),
                                                 glassLibrary: glass)
                .background(Color(nsColor: Palette.HUD.for(scheme).tint))
                .environment(\.colorScheme, scheme))
            func mean(_ pixels: [(Int, Int)]) -> Double { pixels.map { lightness(frame.colorAt(x: $0.0, y: $0.1)!) }.reduce(0, +) / Double(pixels.count) }
            return abs(mean(strokes) - mean(ground))
        }
        // Entry: from the frost starting until it has formed. Exit: from release
        // until the layer is gone, before the strokes fade. One 8-bit step is about 0.6 L* on the
        // dark tint, so a single frame may wobble that much; the old pulse was ten times larger.
        let entry = try stride(from: 0.6, through: 1.3, by: 0.025).map(clarity)
        let exit = try stride(from: 2.5, through: 3.2, by: 0.025).map(clarity)
        #expect(entry.max()! - entry.last! < 1, "the strokes brighten, then dim, as the frost forms: \(entry)")
        #expect(exit.max()! - exit.first! < 1, "the strokes brighten, then dim, as the frost lifts: \(exit)")
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
            // A single render shows one moment, so the mark's cycle is handed in already under
            // way: pressed two seconds ago, as the view would have built it.
            let activity = MarkActivity.of(state: appState.state, isModelPreparing: RecordingIndicatorPresentation.loadingLabel(for: appState.modelLoadState) != nil)
            let start = Date().addingTimeInterval(-2)
            var cycle = KawaIndicatorCycle.next(nil, activity: activity == .transcribing ? .listening : activity, isAudioFlowing: true,
                                                reduceMotion: false, at: start)
            if activity == .transcribing {
                cycle = KawaIndicatorCycle.next(cycle, activity: .transcribing, isAudioFlowing: false,
                                                reduceMotion: false, at: start.addingTimeInterval(1))
            }
            for scheme in [ColorScheme.light, .dark] {
                let view = RiverIndicatorView(appState: appState, markCycle: cycle)
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
