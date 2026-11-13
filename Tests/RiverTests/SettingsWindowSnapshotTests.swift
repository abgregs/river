import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing
@testable import River

/// Renders the Settings window's content, each section and each state of the shortcut recorder
/// in Light and Dark, to PNGs for the side-by-side check against the settings panel study
/// (round 14) and the shortcut recorder study (round 8), and for PR screenshots. Env-gated like
/// the indicator snapshots: the normal suite never writes files. The window's frame, buttons
/// and shadow are macOS's and are not in the image.
@Suite("Settings window snapshots", .enabled(if: ProcessInfo.processInfo.environment["RIVER_SNAPSHOT_DIR"] != nil))
@MainActor
struct SettingsWindowSnapshotTests {
    @Test("write each section, 2x, on light and dark appearance")
    func writeSnapshots() async throws {
        let directory = try snapshotDirectory()
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
                                        updater: UpdaterManager(), shortcutHooks: .inert, selectModel: { _ in })
        model.permissionMissing = true
        // Each section, then the Model section with a choice waiting for a dictation to end,
        // and with a switch that failed.
        let shots = SettingsSection.allCases.map { ($0, $0.rawValue) }
            + [(.model, "model-waiting"), (.model, "model-switch-failed")]
        for (section, shot) in shots {
            model.section = section
            if shot == "model-waiting" {
                appState.apply(modelSelection: ModelSelection(
                    inUse: transcription.currentSelection.inUse, inUseState: .ready,
                    next: ModelSwitch(target: "openai_whisper-base.en", phase: .ready)))
            }
            if shot == "model-switch-failed" {
                transcription.stageFailsForTesting = true
                await transcription.switchModel(to: "openai_whisper-large-v3-v20240930_turbo")
            }
            let size = section == .model ? Constants.settingsModelWindowSize : Constants.settingsWindowSize
            for appearance in Self.appearances {
                try write(model, size: size, appearance: appearance, to: directory.appendingPathComponent("settings-\(shot)-\(appearance.name).png"))
            }
        }
    }

    @Test("write the shortcut recorder's states, 2x, on light and dark appearance")
    func writeRecorderSnapshots() async throws {
        let directory = try snapshotDirectory()
        let controlOptionSpace = Shortcut.combination(keyCode: kVK_Space, modifiers: [.control, .option])
        let controlCommandSpace = Shortcut.combination(keyCode: kVK_Space, modifiers: [.control, .command])
        let held: (SettingsWindowModel) -> Void = { model in
            model.recorder.handle(.modifierChanged(keyCode: 59, isDown: true))
            model.recorder.handle(.modifierChanged(keyCode: 58, isDown: true))
        }
        let pressSpace: (SettingsWindowModel) -> Void = { model in
            model.recorder.handle(.keyDown(keyCode: kVK_Space, modifiers: [.control, .option], isRepeat: false))
        }
        let shots: [RecorderShot] = [
            RecorderShot(name: "recording", steps: [{ $0.recorder.start() }]),
            RecorderShot(name: "held", steps: [{ $0.recorder.start() }, held]),
            RecorderShot(name: "refused-another-app", hooks: Self.hooks(registration: .takenByAnotherApp),
                         steps: [{ $0.recorder.start() }, held, pressSpace]),
            RecorderShot(name: "refused-fn", steps: [{ $0.recorder.start() }, { model in
                model.recorder.handle(.modifierChanged(keyCode: 63, isDown: true))
                model.recorder.handle(.modifierChanged(keyCode: 63, isDown: false))
            }]),
            // An offscreen window has no display to drive SwiftUI's animations, so the save is
            // shown where it starts, the new shortcut held in red, and where it lands; the motion
            // between is checked on device.
            RecorderShot(name: "saving-hold", saved: controlOptionSpace, steps: [{ $0.recorder.start() }, held, pressSpace], wait: 0.02),
            RecorderShot(name: "saved", saved: controlOptionSpace),
            RecorderShot(name: "macos-warning", saved: controlCommandSpace,
                         hooks: Self.hooks(system: [SystemShortcuts.Entry(keyCode: kVK_Space, modifiers: [.control, .command])])),
            RecorderShot(name: "failing", saved: controlOptionSpace, prepare: { $0.apply(dictationRegistration: .takenByAnotherApp) }),
            RecorderShot(name: "busy", prepare: { $0.apply(.recording) }),
        ]
        defer { UserDefaults.standard.removeObject(forKey: Settings.dictationShortcut.name) }
        for shot in shots {
            if let saved = shot.saved {
                UserDefaults.standard.set(saved.rawValue, forKey: Settings.dictationShortcut.name)
            } else {
                UserDefaults.standard.removeObject(forKey: Settings.dictationShortcut.name)
            }
            for appearance in Self.appearances {
                let appState = AppState()
                shot.prepare(appState)
                let model = SettingsWindowModel(appState: appState, capabilities: [], updater: UpdaterManager(),
                                                shortcutHooks: shot.hooks, selectModel: { _ in })
                try write(model, size: Constants.settingsWindowSize, appearance: appearance, steps: shot.steps, wait: shot.wait,
                          to: directory.appendingPathComponent("settings-shortcuts-\(shot.name)-\(appearance.name).png"))
                model.recorder.stop()
            }
        }
    }

    private struct RecorderShot {
        let name: String
        var saved: Shortcut?
        var hooks: ShortcutRecorderHooks = .inert
        var prepare: (AppState) -> Void = { _ in }
        var steps: [(SettingsWindowModel) -> Void] = []
        /// How long after the last step the image is taken.
        var wait: TimeInterval = 0.05
    }

    private static let appearances: [(name: String, appearance: NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]

    private static func hooks(registration: HotKeyRegistration = .registered, system: [SystemShortcuts.Entry] = []) -> ShortcutRecorderHooks {
        ShortcutRecorderHooks(pause: { true }, resume: {}, probe: { _ in registration }, save: { _ in }, systemShortcuts: { system })
    }

    private func snapshotDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["RIVER_SNAPSHOT_DIR"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // Draws the window's content offscreen, runs `steps` with the view on screen so it sees each
    // change as the app would, then writes what it shows.
    private func write(_ model: SettingsWindowModel, size: CGSize, appearance: (name: String, appearance: NSAppearance.Name),
                       steps: [(SettingsWindowModel) -> Void] = [], wait: TimeInterval = 0.05, to url: URL) throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance.appearance)
        let host = NSHostingView(rootView: SettingsWindowView(model: model))
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        for (index, step) in steps.enumerated() {
            step(model)
            RunLoop.main.run(until: Date().addingTimeInterval(index == steps.count - 1 ? wait : 0.05))
        }
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let data = try #require(rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]))
        try data.write(to: url)
    }
}
