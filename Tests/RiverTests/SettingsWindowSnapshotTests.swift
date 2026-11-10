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
    func writeSnapshots() throws {
        let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["RIVER_SNAPSHOT_DIR"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let microphone = MicrophoneCapability()
        microphone.setStatusForTesting(.granted)
        let inputMonitoring = InputMonitoringCapability()
        inputMonitoring.setStatusForTesting(.granted)
        let accessibility = AccessibilityCapability()
        accessibility.setStatusForTesting(.denied)
        let model = SettingsWindowModel(appState: AppState(), capabilities: [microphone, inputMonitoring, accessibility],
                                        updater: UpdaterManager(), selectModel: { _ in })
        model.permissionMissing = true
        for section in SettingsSection.allCases {
            model.section = section
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
                try data.write(to: directory.appendingPathComponent("settings-\(section.rawValue)-\(name).png"))
            }
        }
    }
}
