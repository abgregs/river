import Combine
import CoreGraphics
import Foundation
import os

/// `HotkeyManager`'s answer to "can this be the dictation shortcut?" (spec 0036, Conflicts).
/// The recorder words each one; no copy lives here.
enum ShortcutAvailability: Equatable {
    case available
    /// Available, and on macOS's own list too: saved with the warning, since both run.
    case alsoUsedByMacOS
    case usedByRiver(RiverShortcut)
    case takenByAnotherApp
    /// macOS refused the registration for another reason.
    case refusedByMacOS
}

/// Interprets the dictation shortcut against the activation mode. A lone modifier
/// is read from the typed `TapEvent` stream of `InputMonitoringCapability`; a
/// combination is an exclusive hot key read from `HotKeyRegistry`. Hold mode is
/// inline (press activates, release deactivates); the two tap modes route each
/// completed tap through `TapStateMachine`.
@MainActor
final class HotkeyManager {
    private let inputMonitoring: InputMonitoringCapability
    private let hotKeys: HotKeyRegistry
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "hotkey")

    var onActivate: (() -> Void)?
    var onDeactivate: (() -> Void)?
    /// The cancel gesture fired (planning 0017). `RiverSession` guards it to
    /// `.recording`, so firing outside a recording is a harmless no-op.
    var onCancel: (() -> Void)?
    /// A River hot key was pressed while a lone-modifier dictation key was held in
    /// Hold mode: the user is running a shortcut, not dictating, so the recording
    /// is thrown away with no cue (spec 0036). Guarded to `.recording` like cancel.
    var onDiscard: (() -> Void)?
    /// Whether a recording is live, read on each completed tap in the tap modes.
    /// `RiverSession` answers from its own state, the only "recording" there is.
    var isRecording: () -> Bool = { false }

    private var shortcut: Shortcut
    private var mode: ActivationMode
    private let cancelKeyCode: Int
    private let tapMachine: TapStateMachine
    // Press latch for a lone-modifier shortcut.
    private var isKeyDown = false
    // A River hot key went down during this lone-modifier press, so its release is
    // not a stop (Hold) or a tap (tap modes).
    private var isKeyPressSpent = false
    // A combination press started a Hold recording that has not stopped yet. The
    // key's release and a modifier lifting both stop it, and only the first counts.
    private var isCombinationHeld = false
    // Press latch for the cancel modifier, tracked separately from the activation
    // key so a cancel-key edge never disturbs the activation latch (and vice versa).
    private var isCancelKeyDown = false
    private var cancellables = Set<AnyCancellable>()
    private let registrationSubject = CurrentValueSubject<HotKeyRegistration?, Never>(nil)

    /// What macOS said to the combination's registration; nil for a lone modifier.
    var dictationRegistration: HotKeyRegistration? { registrationSubject.value }
    /// The same, as it changes, for the Settings window's "Not working" line.
    var dictationRegistrations: AnyPublisher<HotKeyRegistration?, Never> { registrationSubject.eraseToAnyPublisher() }
    /// River's shortcuts are paused while the Settings recorder listens (spec 0036, The
    /// recorder): the hot key is unregistered, so the recorder sees its keys, and the tap's
    /// events change nothing.
    private(set) var isPaused = false
    // `resume` was asked for while a modifier was down: the shortcuts come back on the tap's
    // own release of the last one, so that release reaches no latch.
    private var isResumePending = false
    // Whether any modifier is down, as the tap's last event said; followed even while paused.
    private var isModifierHeld = false
    private let resumeDeadline: Duration
    private var resumeDeadlineTask: Task<Void, Never>?
    private let systemShortcuts: () -> [SystemShortcuts.Entry]

    init(
        inputMonitoring: InputMonitoringCapability,
        hotKeys: HotKeyRegistry,
        initialShortcut: Shortcut = Constants.defaultDictationShortcut,
        initialMode: ActivationMode = Constants.defaultActivationMode,
        cancelKeyCode: Int = Constants.cancelKeyCode,
        resumeDeadline: Duration = .seconds(Constants.shortcutResumeDeadlineSeconds),
        systemShortcuts: @escaping () -> [SystemShortcuts.Entry] = SystemShortcuts.enabled
    ) {
        self.inputMonitoring = inputMonitoring
        self.hotKeys = hotKeys
        self.shortcut = initialShortcut
        self.mode = initialMode
        self.cancelKeyCode = cancelKeyCode
        self.resumeDeadline = resumeDeadline
        self.systemShortcuts = systemShortcuts
        self.tapMachine = TapStateMachine(mode: initialMode, windowMs: Constants.doubleTapWindowMs)
    }

    func start() async {
        bindEventStream()
        registerCombination()
        await inputMonitoring.startTap()
    }

    func stop() async {
        cancellables.removeAll()
        cancelPendingResume()
        hotKeys.unregister(.dictation)
        await inputMonitoring.stopTap()
        resetLatches()
        isCancelKeyDown = false
    }

    /// Live-apply for the dictation shortcut. Moves the hot key registration and
    /// resets the press latches so a half-press of the old shortcut can't fire a
    /// phantom deactivate against the new one. Does NOT touch the tap machine: the
    /// new shortcut stops an active recording because the session still reports it
    /// (a stale double-tap `awaiting` state self-clears via the time window).
    func setShortcut(_ newShortcut: Shortcut) {
        guard shortcut != newShortcut else { return }
        logger.info("Dictation shortcut changed: \(self.shortcut.rawValue, privacy: .public) -> \(newShortcut.rawValue, privacy: .public)")
        hotKeys.unregister(.dictation)
        registrationSubject.send(nil)
        shortcut = newShortcut
        resetLatches()
        // Registered at once only while running and not paused; before `start` there is
        // nothing to deliver its events to, and `start` or `resume` registers it.
        if !cancellables.isEmpty, !isPaused { registerCombination() }
    }

    /// Pauses River's shortcuts for the Settings recorder. Pausing again while a resume
    /// waits for a key to come up keeps them paused.
    func pause() {
        cancelPendingResume()
        guard !isPaused else { return }
        isPaused = true
        hotKeys.unregister(.dictation)
        logger.info("Shortcuts paused for the recorder")
    }

    /// Restores River's shortcuts once every modifier key is up, as the tap reports them: at
    /// once if none is down, else on the tap's release of the last one, which reaches no
    /// latch, so the keys of the shortcut just recorded never start or stop a dictation. A
    /// tap that falls silent can't keep them paused: they come back after `resumeDeadline`.
    /// Registering again also retries a combination that failed, so recording the same
    /// shortcut once another app lets go of it fixes it.
    func resume() {
        guard isPaused, !isResumePending else { return }
        guard isModifierHeld else { return finishResume() }
        isResumePending = true
        resumeDeadlineTask = Task { @MainActor [weak self, resumeDeadline] in
            try? await Task.sleep(for: resumeDeadline)
            guard let self, !Task.isCancelled, self.isResumePending else { return }
            self.logger.info("No key-up from the tap; resuming shortcuts anyway")
            self.finishResume()
        }
    }

    private func finishResume() {
        cancelPendingResume()
        isPaused = false
        resetLatches()
        isCancelKeyDown = false
        if !cancellables.isEmpty { registerCombination() }
        logger.info("Shortcuts resumed")
    }

    private func cancelPendingResume() {
        isResumePending = false
        resumeDeadlineTask?.cancel()
        resumeDeadlineTask = nil
    }

    /// Whether `candidate` can be the dictation shortcut, and if not, why (spec 0036,
    /// Conflicts): River's own shortcuts first, then whether macOS will register a
    /// combination, then macOS's own list.
    func availability(of candidate: Shortcut) -> ShortcutAvailability {
        if let owner = RiverShortcut.allCases.first(where: { $0.shortcut == candidate }) {
            return .usedByRiver(owner)
        }
        switch registration(of: candidate) {
        case .registered: break
        case .takenByAnotherApp: return .takenByAnotherApp
        case .refused: return .refusedByMacOS
        }
        return SystemShortcuts.contains(candidate, in: systemShortcuts()) ? .alsoUsedByMacOS : .available
    }

    // A lone modifier needs no registration: the tap watches it. While River holds the
    // combination itself, its own registration answers, since a probe would find River's hot
    // key and read it as another app's.
    private func registration(of candidate: Shortcut) -> HotKeyRegistration {
        guard case .combination(let keyCode, let modifiers) = candidate else { return .registered }
        if !isPaused, candidate == shortcut, let own = registrationSubject.value { return own }
        return hotKeys.probe(keyCode: UInt32(keyCode), modifiers: modifiers.carbonFlags)
    }

    /// Live-apply for the activation mode. Resets the press latch and hands the
    /// new mode to the tap machine, which clears a half-finished double tap.
    func setActivationMode(_ newMode: ActivationMode) {
        guard mode != newMode else { return }
        logger.info("Activation mode changed: \(self.mode.rawValue, privacy: .public) -> \(newMode.rawValue, privacy: .public)")
        mode = newMode
        resetLatches()
        tapMachine.setMode(newMode)
    }

    // internal for testability — subscribes to both event streams without creating
    // a real tap or hot key, so tests can drive synthetic events through.
    func bindEventStream() {
        guard cancellables.isEmpty else { return }
        inputMonitoring.events
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &cancellables)
        hotKeys.events
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &cancellables)
    }

    private func registerCombination() {
        guard case .combination(let keyCode, let modifiers) = shortcut else { return }
        registrationSubject.send(hotKeys.register(
            .dictation, keyCode: UInt32(keyCode), modifiers: modifiers.carbonFlags
        ))
    }

    // A key River doesn't know as a modifier keeps its latch as it is.
    private static func isDown(_ keyCode: Int, in flags: CGEventFlags) -> Bool? {
        ModifierKey(rawValue: keyCode)?.isDown(rawFlags: flags.rawValue)
    }

    // The flags of keys a person holds down; Caps Lock's stays set while it is on.
    private static let modifierFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand, .maskSecondaryFn]

    private func resetLatches() {
        isKeyDown = false
        isKeyPressSpent = false
        isCombinationHeld = false
    }

    // internal for testability — pure interpretation of the tap. `.flagsChanged`
    // for a lone-modifier shortcut moves the press latch to what the key's own bit
    // says (`ModifierKey`): the keycode names the side, and an event that repeats a
    // state, or follows a missed one, is no edge (see activation-key-and-mode.md).
    // Hold mode fires on each edge; tap modes act only on the completing (key-up)
    // edge of a tap and delegate start/stop to the tap machine — so holding the
    // key in a tap mode is just one tap. For a combination held in Hold mode, the
    // tap reports its modifiers lifting.
    func handle(_ event: TapEvent) {
        if case .flagsChanged(_, let flags) = event {
            isModifierHeld = !flags.isDisjoint(with: Self.modifierFlags)
        }
        guard !isPaused else {
            if isResumePending, !isModifierHeld { finishResume() }
            return
        }
        switch event {
        case .flagsChanged(let keyCode, let flags):
            // The cancel modifier (planning 0017) is interpreted off the same
            // already-watched `.flagsChanged` stream — no second tap, no mask change,
            // so the 0006 least-privilege posture is untouched. fn is never the
            // dictation shortcut (spec 0036), so it always cancels.
            if Int(keyCode) == cancelKeyCode {
                handleCancelKey(isDown: Self.isDown(cancelKeyCode, in: flags) ?? isCancelKeyDown)
                return
            }
            switch shortcut {
            case .modifier(let watchedKeyCode):
                guard Int(keyCode) == watchedKeyCode else { return }
                handleModifierEdge(isDown: Self.isDown(watchedKeyCode, in: flags) ?? isKeyDown)
            case .combination(_, let modifiers):
                // Lifting any of the combination's modifiers ends a Hold recording,
                // even while the key is still down: the shortcut is no longer held.
                guard isCombinationHeld, !flags.contains(modifiers.eventFlags) else { return }
                isCombinationHeld = false
                fireDeactivate()
            }
        case .tapDisabled:
            // Capability self-heals; nothing for the manager to do.
            break
        }
    }

    // internal for testability — pure interpretation of a River hot key.
    func handle(_ event: HotKeyEvent) {
        guard !isPaused else { return }
        switch (shortcut, event) {
        case (.combination, .pressed(.dictation)):
            // Hold starts on the press. The tap modes wait for the release, so
            // holding the combination is one tap, as with a lone modifier.
            guard mode == .hold, !isCombinationHeld else { return }
            isCombinationHeld = true
            fireActivate()
        case (.combination, .released(.dictation)):
            switch mode {
            case .hold:
                guard isCombinationHeld else { return }
                isCombinationHeld = false
                fireDeactivate()
            case .singleTap, .doubleTap:
                completeTap()
            }
        case (.modifier, .pressed(let id)):
            // Another River shortcut went down while the dictation modifier is held:
            // the modifier is part of that shortcut, not a dictation.
            guard isKeyDown, !isKeyPressSpent else { return }
            isKeyPressSpent = true
            logger.info("Hot key \(id.rawValue, privacy: .public) pressed during the dictation key; that press is not a dictation")
            if mode == .hold { onDiscard?() }
        default:
            break
        }
    }

    private func handleModifierEdge(isDown: Bool) {
        guard isDown != isKeyDown else { return }
        isKeyDown = isDown
        if !isKeyDown, isKeyPressSpent {
            isKeyPressSpent = false
            return
        }
        switch mode {
        case .hold:
            if isKeyDown { fireActivate() } else { fireDeactivate() }
        case .singleTap, .doubleTap:
            guard !isKeyDown else { return }
            completeTap()
        }
    }

    private func completeTap() {
        switch tapMachine.handleTap(isRecording: isRecording()) {
        case .start: fireActivate()
        case .stop: fireDeactivate()
        case .none: break
        }
    }

    // The cancel modifier keeps its own latch and fires on the press (key-down) edge
    // only, so one tap of the cancel key is one cancel. Mode-agnostic: cancel works
    // identically in Hold and both tap modes.
    private func handleCancelKey(isDown: Bool) {
        guard isDown != isCancelKeyDown else { return }
        isCancelKeyDown = isDown
        guard isCancelKeyDown else { return }
        logger.info("Cancel gesture (keycode \(self.cancelKeyCode, privacy: .public))")
        onCancel?()
    }

    private func fireActivate() {
        logger.info("Activate (shortcut \(self.shortcut.rawValue, privacy: .public), mode \(self.mode.rawValue, privacy: .public))")
        onActivate?()
    }

    private func fireDeactivate() {
        logger.info("Deactivate (shortcut \(self.shortcut.rawValue, privacy: .public), mode \(self.mode.rawValue, privacy: .public))")
        onDeactivate?()
    }
}
