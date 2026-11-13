import AppKit
import Observation
import SwiftUI

/// What recording a shortcut reaches outside the Settings window: River's shortcuts, paused
/// while the recorder listens; macOS's answer to a combination; the setting; and macOS's own
/// shortcut list. Closures, as `selectModel` is, so the window never reaches past the session
/// and a snapshot or test needs no session.
struct ShortcutRecorderHooks {
    /// Pauses River's shortcuts; false while a dictation runs, when recording is unavailable.
    var pause: () -> Bool
    /// Brings River's shortcuts back once every modifier key is up, so the keys just
    /// recorded never reach them.
    var resume: () -> Void
    var probe: (Shortcut) -> HotKeyRegistration
    var save: (Shortcut) -> Void
    var systemShortcuts: () -> [SystemShortcuts.Entry]

    /// Accepts every shortcut and reaches nothing.
    static let inert = ShortcutRecorderHooks(
        pause: { true }, resume: {}, probe: { _ in .registered }, save: { _ in }, systemShortcuts: { [] }
    )
}

/// The dictation shortcut's recorder (spec 0036, The recorder). While it records, it takes the
/// window's key presses, feeds them to `ShortcutRecorder`, and checks and saves what it hears;
/// River's shortcuts are paused meanwhile, and HotkeyManager brings them back once every key is
/// up. Esc, Cancel, a click anywhere but the button, or the window losing key stops it, keeping
/// the saved shortcut.
@MainActor
@Observable
final class ShortcutRecorderModel {
    enum Phase: Equatable {
        case idle
        case recording
        /// Just saved: the outline holds the new shortcut in red, then settles to ink.
        case saving(Shortcut)
    }

    private(set) var phase: Phase = .idle
    /// The modifiers held while recording.
    private(set) var held: ShortcutModifiers = []
    /// A refused attempt, shown dimmed beside the dot until a modifier goes down.
    private(set) var tried: ShortcutText.Keys?
    /// The line under the row while recording: how to record, or why a shortcut was refused.
    private(set) var line: RecorderLine?
    /// One more for each refusal: the outline shakes once.
    private(set) var refusals = 0
    /// When recording began: the dot's pulse keeps this one clock through every redraw.
    private(set) var startedAt = Date()
    /// Whether macOS also uses the saved shortcut, checked when the pane appears and on a save.
    private(set) var isSystemShortcut = false

    /// The Record button's frame in the window, top-left origin: a click outside it stops.
    @ObservationIgnored var buttonFrame: CGRect = .zero

    @ObservationIgnored private let hooks: ShortcutRecorderHooks
    @ObservationIgnored private var recorder = ShortcutRecorder()
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var resignObserver: NSObjectProtocol?
    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var settleTask: Task<Void, Never>?

    init(hooks: ShortcutRecorderHooks) {
        self.hooks = hooks
    }

    var isRecording: Bool { phase == .recording }

    /// Checks the saved shortcut against macOS's own list, for the line that stays while true.
    func refresh(saved: Shortcut) {
        isSystemShortcut = SystemShortcuts.contains(saved, in: hooks.systemShortcuts())
    }

    func toggle() {
        isRecording ? stop() : start()
    }

    func start() {
        // Pausing again during a save keeps River's shortcuts paused if their resume is still
        // waiting for a key to come up.
        guard !isRecording, hooks.pause() else { return }
        settleTask?.cancel()
        recorder = ShortcutRecorder()
        held = []
        tried = nil
        line = .recordingDictation
        startedAt = Date()
        phase = .recording
        window = NSApplication.shared.keyWindow
        installMonitor()
    }

    /// Stops listening and keeps the saved shortcut.
    func stop() {
        guard isRecording else { return }
        finish()
        phase = .idle
    }

    // internal for testability — one key event, as the window's monitor delivers it.
    func handle(_ event: ShortcutRecorder.Event) {
        guard isRecording else { return }
        switch recorder.handle(event) {
        case .none:
            held = recorder.held
            if !held.isEmpty, tried != nil {
                tried = nil
                line = .recordingDictation
            }
        case .stop:
            stop()
        case .clear:
            refuse(.cannotClear, tried: nil)
        case .bareKey(let keyCode):
            refuse(.needsModifier, tried: ShortcutText.Keys(keys: [ShortcutText.keyName(keyCode)]))
        case .candidate(let shortcut):
            switch ShortcutCheck.check(shortcut, registration: hooks.probe, system: hooks.systemShortcuts()) {
            case .save: save(shortcut, macOSAlsoUses: false)
            case .saveWithWarning: save(shortcut, macOSAlsoUses: true)
            case .refuse(let reason): refuse(.refused(reason), tried: ShortcutText.keys(shortcut))
            }
        }
    }

    private func refuse(_ reason: RecorderLine, tried attempt: ShortcutText.Keys?) {
        line = reason
        tried = attempt
        held = recorder.held
        refusals += 1
        AccessibilityNotification.Announcement(reason.text).post()
    }

    private func save(_ shortcut: Shortcut, macOSAlsoUses: Bool) {
        finish()
        hooks.save(shortcut)
        isSystemShortcut = macOSAlsoUses
        if macOSAlsoUses { AccessibilityNotification.Announcement(RecorderLine.macOSAlsoUses.text).post() }
        phase = .saving(shortcut)
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Constants.recorderSaveSeconds))
            guard !Task.isCancelled, let self, case .saving = self.phase else { return }
            self.phase = .idle
        }
    }

    private func finish() {
        removeMonitor()
        held = []
        tried = nil
        line = nil
        hooks.resume()
    }

    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) ?? event }
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    // Keys are the recorder's while it listens, so they reach nothing else in the window; a
    // click still reaches what it clicked.
    private func receive(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            handle(.keyDown(keyCode: Int(event.keyCode), modifiers: Self.modifiers(event.modifierFlags), isRepeat: event.isARepeat))
            return nil
        case .flagsChanged:
            let keyCode = Int(event.keyCode)
            if let isDown = ShortcutRecorder.isDown(keyCode: keyCode, rawFlags: event.modifierFlags.rawValue) {
                handle(.modifierChanged(keyCode: keyCode, isDown: isDown))
            }
            return nil
        case .leftMouseDown:
            if event.window !== window || !buttonFrame.contains(Self.location(of: event)) { stop() }
            return event
        default:
            return event
        }
    }

    private static func modifiers(_ flags: NSEvent.ModifierFlags) -> ShortcutModifiers {
        var modifiers: ShortcutModifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }

    // The click in the window's content, top-left origin, as SwiftUI's global frames are.
    private static func location(of event: NSEvent) -> CGPoint {
        guard let view = event.window?.contentView else { return .zero }
        let point = view.convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: view.isFlipped ? point.y : view.bounds.height - point.y)
    }
}
