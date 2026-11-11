import AppKit
import SwiftUI
import Testing
@testable import River

/// Renders the Settings window's content, each section in Light and Dark, to PNGs for the
/// side-by-side check against the settings panel study (round 14) and for PR screenshots.
/// Env-gated like the indicator snapshots: the normal suite never writes files. The window's
/// frame, buttons and shadow are macOS's and are not in the image.
@Suite("Settings window snapshots", .enabled(if: ProcessInfo.processInfo.environment["RIVER_SNAPSHOT_DIR"] != nil))
@MainActor
struct SettingsWindowSnapshotTests {
    @Test("write each section, 2x, on light and dark appearance")
    func writeSnapshots() async throws {
        let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["RIVER_SNAPSHOT_DIR"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let microphone = MicrophoneCapability()
        microphone.setStatusForTesting(.granted)
        let inputMonitoring = InputMonitoringCapability()
        inputMonitoring.setStatusForTesting(.granted)
        let accessibility = AccessibilityCapability()
        accessibility.setStatusForTesting(.denied)
        let appState = AppState()
        let transcription = TranscriptionManager()
        transcription.setModelLoadStateForTesting(.ready)
        transcription.skipLoadForTesting = true
        appState.bind(transcription: transcription)
        let model = SettingsWindowModel(appState: appState, capabilities: [microphone, inputMonitoring, accessibility],
                                        updater: UpdaterManager(), selectModel: { _ in })
        model.permissionMissing = true
        // Each section, then the Model section with a choice waiting for a dictation to end,
        // and with a switch that failed.
        let shots = SettingsSection.allCases.map { ($0, $0.rawValue) }
            + [(.model, "model-waiting"), (.model, "model-switch-failed")]
        for (section, shot) in shots {
            model.section = section
            appState.apply(waitingModel: shot == "model-waiting" ? "openai_whisper-base.en" : nil)
            if shot == "model-switch-failed" {
                transcription.stageFailsForTesting = true
                await transcription.switchModel(to: "openai_whisper-large-v3-v20240930_turbo")
            }
            let size = section == .model ? Constants.settingsModelWindowSize : Constants.settingsWindowSize
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                                      backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                let host = NSHostingView(rootView: SettingsWindowView(model: model))
                host.frame = NSRect(origin: .zero, size: size)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                let data = try #require(rep.representation(using: .png, properties: [:]))
                try data.write(to: directory.appendingPathComponent("settings-\(shot)-\(name).png"))
            }
        }
    }
}
