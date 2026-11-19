import AppKit
import Foundation
import SwiftUI
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "app")

    let accessibility = AccessibilityCapability()
    let microphone = MicrophoneCapability()
    let inputMonitoring = InputMonitoringCapability()
    let settings = SettingsStore()
    let system = SystemAvailabilityMonitor()
    let hotKeys = HotKeyRegistry()
    // Lazy so the manager loads the persisted `selectedModel` (planning 0021) at
    // launch, not the compile-time default — otherwise a user who picked a different
    // model would load `small.en` first and immediately reload on the startup
    // subscription emission. `settings` is a stored property, so this must be lazy to
    // read it during construction.
    private(set) lazy var transcription = TranscriptionManager(
        modelName: settings.value(for: Settings.selectedModel)
    )
    let appState = AppState()

    private(set) lazy var session: RiverSession = {
        RiverSession(
            accessibility: accessibility,
            microphone: microphone,
            inputMonitoring: inputMonitoring,
            hotkey: HotkeyManager(
                inputMonitoring: inputMonitoring,
                hotKeys: hotKeys,
                initialShortcut: settings.value(for: Settings.dictationShortcut),
                initialMode: settings.value(for: Settings.activationMode)
            ),
            audio: AudioCaptureManager(microphone: microphone),
            textInsertion: TextInsertionManager(accessibility: accessibility),
            transcription: transcription,
            settings: settings,
            system: system
        )
    }()

    var capabilities: [any Capability] { [accessibility, microphone, inputMonitoring] }

    private(set) lazy var onboarding: OnboardingCoordinator = {
        OnboardingCoordinator(capabilities: capabilities)
    }()

    private(set) lazy var recordingIndicator: RecordingIndicatorCoordinator = {
        RecordingIndicatorCoordinator(appState: appState)
    }()

    private(set) lazy var soundFeedback: SoundFeedbackController = {
        SoundFeedbackController(appState: appState, settings: settings)
    }()

    let updater = UpdaterManager()

    private(set) lazy var settingsWindow: SettingsWindowController = {
        SettingsWindowController(
            appState: appState, capabilities: capabilities, updater: updater,
            shortcutHooks: { [unowned self] row in self.shortcutHooks(for: row) },
            selectModel: { [weak self] model in self?.session.selectModel(model) },
            deleteModel: { [weak self] model in try self?.session.deleteModel(model) }
        )
    }()

    // A row's recorder reach (planning 0036, The recorder): River's shortcuts through the
    // session, never past it, and the row's setting through the store.
    private func shortcutHooks(for row: RiverShortcut) -> ShortcutRecorderHooks {
        ShortcutRecorderHooks(
            pause: { [weak self] in self?.session.pauseShortcuts() ?? false },
            resume: { [weak self] in self?.session.resumeShortcuts() },
            check: { [weak self] in self?.session.availability(of: $0, for: row) ?? .available },
            save: { [weak self] shortcut in self?.save(shortcut, for: row) }
        )
    }

    private func save(_ shortcut: Shortcut, for row: RiverShortcut) {
        switch row {
        case .dictate: settings.setValue(shortcut, for: Settings.dictationShortcut)
        case .pasteLast: settings.setValue(shortcut, for: Settings.pasteLastShortcut)
        case .copyLast: settings.setValue(shortcut, for: Settings.copyLastShortcut)
        case .toggleLiveText: settings.setValue(shortcut, for: Settings.liveTextShortcut)
        case .cancelRecording: break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Application did finish launching")
        // Before anything reads the dictation shortcut: `session` is built on first use.
        settings.migrateActivationKeyCode()
        appState.bind(to: session)
        appState.bind(transcription: transcription)
        appState.bind(microphone: microphone)
        onboarding.start()
        recordingIndicator.start()
        soundFeedback.start()
        updater.start()
        settingsWindow.start()
        Task { @MainActor in
            do { try await session.start() }
            catch { logger.error("Failed to start session: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)") }
            for capability in capabilities { await capability.recheck() }
            onboarding.presentIfNeeded()
        }
        // Model load is fire-and-forget on its own schedule (per the architecture:
        // "Default model loads on launch, not blocking the session"). First launch
        // may download the model; subsequent launches use the cached copy.
        Task { @MainActor in
            try? await transcription.loadModel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in await session.stop() }
    }
}
