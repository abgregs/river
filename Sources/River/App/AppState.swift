import Combine
import Foundation
import Observation

/// Schedules AppState's timers: the status's reveal and hold (planning 0004). Injected so tests fire them synchronously instead of waiting on
/// wall-clock time (planning 0018 AC4; the injectable-clock pattern of `TapStateMachine`).
/// Returns a token whose cancellation stops a pending action — reassigning it (a newer error)
/// cancels the previous timer.
typealias TimerScheduler = @MainActor (_ after: TimeInterval, _ action: @escaping @MainActor () -> Void) -> AnyCancellable

/// What the status in the mark's place says (planning 0004).
enum DictationStatus: Equatable {
    /// The model's state while a dictation waits for it, then ready, or failed with the
    /// recording kept.
    case model(StatusRing.Phase)
    /// The app dictated into left the front: River stopped typing and holds the text.
    case held
    /// A cycle error (planning 0018).
    case error(ErrorStatus)
}

/// Observable bridge from the `AppDelegate`-owned `RiverSession` (Combine
/// publishers) to SwiftUI. The menu bar — and the recording-indicator HUD
/// (planning 0002/0018/0020) — observe this; the session itself stays UI-agnostic.
@MainActor
@Observable
final class AppState {
    private(set) var state: RiverState = .idle
    private(set) var errorMessage: String?
    private(set) var notice: String?
    /// Model load lifecycle — `.loading` until the model is warm, then `.ready`.
    /// Menu bar reads this to show "Downloading model…" / "Preparing model…" during launch.
    private(set) var modelLoadState: ModelLoadState = .loading
    // The model in use and a model loading beside it, for the Settings Model section.
    private(set) var modelSelection = ModelSelection(inUse: Constants.defaultModel, inUseState: .loading, next: nil)
    /// Live input level (0...1) during recording (planning 0020). Zero at rest and
    /// whenever not recording, so the HUD meter sits still outside a capture.
    private(set) var inputLevel: Float = 0
    /// Whether the microphone has delivered audio this recording: true from the first level
    /// reading during `.recording` (the first buffer always publishes), false in any other state.
    /// The indicator starts its voice layer on it, so a dead microphone never looks live.
    private(set) var isAudioFlowing = false
    /// Whether the session has retained a transcript for recovery (planning 0019).
    /// Availability only — the retained transcript itself stays in the session.
    private(set) var hasLastTranscript: Bool = false
    /// The current recording's streaming transcript (0025 prototype), shown in the
    /// transcript panel. Empty when streaming is off or nothing has been decoded yet.
    private(set) var liveTranscript: String = ""
    /// Whether the live text shows above the indicator; hidden by default, and only its
    /// shortcut changes it (planning 0034, decision 2).
    private(set) var isLiveTextShown = false
    /// Whether the most recent recording was canceled (planning 0017) rather than stopped.
    /// Set as the state leaves `.recording`, which `apply(_:)` sees one change at a time:
    /// only a cancel goes straight to `.idle`, and a stop always passes through
    /// `.processing`. An observer that reads `state` later can miss that `.processing`,
    /// since an all-silence recording leaves it in the same turn (planning 0023), so it
    /// reads this instead of inferring a cancel from `.recording → .idle`.
    private(set) var lastRecordingWasCanceled = false
    /// Whether the most recent recording was discarded silently because its key was
    /// part of another River shortcut (spec 0036). Not a cancel: no cue plays.
    private(set) var lastRecordingWasDiscarded = false
    /// What macOS said to each combination River holds: a refusal is the Settings window's
    /// "Not working" line on that row and its sidebar badge. A lone modifier has none.
    private(set) var shortcutRegistrations: [RiverShortcut: HotKeyRegistration] = [:]
    /// The status in the mark's place (planning 0004): the model's state when a dictation ends
    /// before the model is ready, text River held, or a cycle error. Nil while nothing shows. The
    /// indicator draws it once the mark's panel has gone.
    private(set) var dictationStatus: DictationStatus?
    /// How far each downloading model has got, 0 to 1, by name, and where a failed download
    /// stopped (planning 0004): the status ring beside the indicator and in Settings.
    private(set) var downloadProgress: [String: Double] = [:]
    /// How many recordings a failed load kept, for Settings' "1 recording kept".
    private(set) var keptRecordingCount = 0
    /// Whether a dictation that has ended waits for the model, for the menu's Cancel Dictation.
    private(set) var isDictationWaiting = false
    // Set by the session's `discards` signal, which arrives just before that
    // recording's `.idle`; consumed as the state leaves `.recording`.
    @ObservationIgnored private var isDiscardPending = false

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private let schedule: TimerScheduler
    // The status's timers, and whether the hand-off has passed since the release: the panel
    // has gone, so a status set now shows at once.
    @ObservationIgnored private var statusReveal: AnyCancellable?
    @ObservationIgnored private var statusHold: AnyCancellable?
    @ObservationIgnored private var isRevealDue = false

    // `nil` default (resolved to `liveScheduler` in this isolated init body)
    // rather than a default-argument reference to the main-actor static, which
    // Swift 6 forbids from the nonisolated context where defaults are evaluated.
    init(schedule: TimerScheduler? = nil) {
        self.schedule = schedule ?? AppState.liveScheduler
    }

    func bind(to session: RiverSession) {
        session.state
            .sink { [weak self] newState in self?.apply(newState) }
            .store(in: &cancellables)
        session.errors
            .sink { [weak self] error in self?.apply(error) }
            .store(in: &cancellables)
        session.notices
            .sink { [weak self] notice in self?.apply(notice: notice) }
            .store(in: &cancellables)
        session.discards
            .sink { [weak self] in self?.applyDiscard() }
            .store(in: &cancellables)
        session.lastTranscriptAvailable
            .sink { [weak self] available in self?.apply(hasLastTranscript: available) }
            .store(in: &cancellables)
        session.liveTranscript
            .sink { [weak self] text in self?.apply(liveTranscript: text) }
            .store(in: &cancellables)
        session.isLiveTextShown
            .sink { [weak self] shown in self?.apply(isLiveTextShown: shown) }
            .store(in: &cancellables)
        session.shortcutRegistrations
            .sink { [weak self] registrations in self?.apply(shortcutRegistrations: registrations) }
            .store(in: &cancellables)
        session.dictationEvents
            .sink { [weak self] event in self?.apply(dictationEvent: event) }
            .store(in: &cancellables)
        session.keptRecordingCount
            .sink { [weak self] count in self?.apply(keptRecordingCount: count) }
            .store(in: &cancellables)
    }

    // internal for testability — wires the model load state publisher so the
    // menu bar observes downloading/loading/ready without coupling to the manager.
    func bind(transcription: TranscriptionManager) {
        transcription.modelLoadState
            .sink { [weak self] loadState in self?.apply(modelLoadState: loadState) }
            .store(in: &cancellables)
        transcription.selection
            .sink { [weak self] selection in self?.apply(modelSelection: selection) }
            .store(in: &cancellables)
        transcription.downloadProgress
            .sink { [weak self] progress in self?.apply(downloadProgress: progress) }
            .store(in: &cancellables)
    }

    // internal for testability — wires the mic's throttled level publisher so the
    // HUD meter observes input level without the level path crossing through the
    // session (mirrors `bind(transcription:)`; planning 0020). The mic is the one
    // capture-unit owner and computes the level; this only forwards it.
    func bind(microphone: MicrophoneCapability) {
        microphone.inputLevels
            .sink { [weak self] level in self?.apply(inputLevel: level) }
            .store(in: &cancellables)
    }

    // internal for testability — the state-update entry point (also used by
    // `bind`). A fresh recording clears a stale error so the menu doesn't show
    // last cycle's failure over a new one. A recording-context notice is tied to
    // the live recording, so it clears the moment that recording ends.
    func apply(_ newState: RiverState) {
        let wasRecording = state == .recording
        if state == .recording && newState != .recording {
            lastRecordingWasDiscarded = isDiscardPending
            lastRecordingWasCanceled = newState == .idle && !isDiscardPending
            isDiscardPending = false
        }
        state = newState
        switch newState {
        case .recording: clearStatus()
        case .processing: if wasRecording { scheduleReveal() }
        case .idle: settleStatus()
        }
        if newState == .recording {
            errorMessage = nil
            // A fresh recording also clears a notice left by the previous one — a cancel
            // sends `.idle` and *then* its notice, so the clear below cannot catch it and
            // the message otherwise rode into the next recording (planning 0017).
            notice = nil
        }
        if newState != .recording {
            notice = nil
            // The meter sits at rest outside a live recording; a late buffer must
            // not leave the last level frozen on screen after the cycle ends.
            inputLevel = 0
            isAudioFlowing = false
        }
    }

    // internal for testability — the next recording end is a silent discard.
    func applyDiscard() {
        isDiscardPending = true
    }

    // internal for testability — a recording-context notice (e.g. a live
    // activation-settings change). Set during `.recording`; see `apply(_:)` for
    // the clear-on-end lifecycle.
    func apply(notice: String) {
        self.notice = notice
    }

    // internal for testability — the error-update entry point (also used by
    // `bind`). The single choke point where a cycle error becomes display text,
    // so `/Users/<name>` paths are redacted exactly once before reaching a
    // screen (ADR 0002).
    func apply(_ error: RiverError) {
        errorMessage = LogRedaction.redactUserPaths(error.localizedDescription)
        // The same error as the status in the mark's place (planning 0018). It is fixed copy
        // per error *kind*, no user content, so it needs no redaction; the redacted framework
        // message stays on `errorMessage` only. The newest status owns the hold.
        show(.error(ErrorStatusPresentation.status(for: error)))
    }

    // internal for testability — the model load state entry point (also used by
    // `bind(transcription:)`). Drives the menu bar's download/load/ready label, and the status
    // row: a wait follows the model through preparing to ready, and a failure shown ends early
    // once the model loads after all.
    func apply(modelLoadState: ModelLoadState) {
        self.modelLoadState = modelLoadState
        // A wait ends once the model is ready or has failed, whether or not its row has shown:
        // the session has nothing left to cancel, so Cancel Dictation leaves the menu.
        if modelLoadState == .ready || modelLoadState == .failed { isDictationWaiting = false }
        switch dictationStatus {
        case .model(.downloading), .model(.preparing):
            if modelLoadState == .ready {
                show(.model(.ready))
            } else if let phase = waitingPhase {
                dictationStatus = .model(phase)
            }
        case .model(.failed):
            if modelLoadState == .ready { endHold() }
        default:
            break
        }
    }

    // internal for testability — the session's dictation events (also used by `bind`).
    func apply(dictationEvent event: DictationEvent) {
        switch event {
        case .waitingForModel:
            isDictationWaiting = true
            showWaitIfDue()
        case .recordingKept:
            isDictationWaiting = false
            show(.model(.failed))
        case .textHeld:
            show(.held)
        }
    }

    // internal for testability — each model's download fraction (also used by
    // `bind(transcription:)`).
    func apply(downloadProgress progress: [String: Double]) {
        downloadProgress = progress
    }

    /// How far the model in use has downloaded, for the row beside the indicator: while it
    /// downloads, and where a failed download stopped. Nil otherwise.
    var downloadFraction: Double? { downloadProgress[modelSelection.inUse] }

    // internal for testability — the session's kept recordings (also used by `bind`).
    func apply(keptRecordingCount count: Int) {
        keptRecordingCount = count
    }

    /// Whether the mark's panel leaves before River is idle: the dictation waits for the model,
    /// or a status is set, which shows only once the panel has gone (planning 0004).
    var hidesPanel: Bool {
        state == .processing && (isDictationWaiting || dictationStatus != nil)
    }

    // A fresh dictation starts with nothing in the mark's place.
    private func clearStatus() {
        dictationStatus = nil
        statusReveal = nil
        statusHold = nil
        isRevealDue = false
        isDictationWaiting = false
    }

    // A wait's status is revealed once the panel has left after the release and a beat has
    // passed, and only if the dictation still waits for the model then: a load that finishes
    // sooner shows nothing.
    private func scheduleReveal() {
        clearStatus()
        statusReveal = schedule(KawaIndicatorTimeline.statusHandOff) { [weak self] in
            guard let self else { return }
            self.statusReveal = nil
            self.isRevealDue = true
            self.showWaitIfDue()
        }
    }

    private func showWaitIfDue() {
        guard isRevealDue, dictationStatus == nil, isDictationWaiting, state == .processing, let phase = waitingPhase else { return }
        show(.model(phase))
    }

    // The model's phase while a dictation waits for it: nil once it is ready or has failed.
    private var waitingPhase: StatusRing.Phase? {
        switch modelLoadState {
        case .downloading: .downloading
        case .loading: .preparing
        case .ready, .failed: nil
        }
    }

    // A status set while the panel is still up shows only after the hand-off, so its hold adds
    // that time: it stays `statusHoldSeconds` on screen.
    private func show(_ status: DictationStatus) {
        dictationStatus = status
        let handOff = state != .idle && !isRevealDue ? KawaIndicatorTimeline.statusHandOff : 0
        switch status {
        case .model(.failed), .held, .error:
            statusHold = schedule(handOff + Constants.statusHoldSeconds) { [weak self] in self?.endHold() }
        case .model(.ready):
            // Until the check has been revealed and read.
            let check = Constants.statusRingCheckDelaySeconds + Constants.statusRingCheckSeconds
            statusHold = schedule(handOff + check + Constants.statusReadyHoldSeconds) { [weak self] in self?.endHold() }
        case .model(.downloading), .model(.preparing):
            break
        }
    }

    private func endHold() {
        statusHold = nil
        if state == .idle { dictationStatus = nil }
    }

    // Back at idle: a wait that ended without the model (Cancel Dictation) goes with the cycle,
    // and so does a reveal still to come; a status whose hold has run out goes too. A hold
    // still running carries on.
    private func settleStatus() {
        switch dictationStatus {
        case .model(.downloading), .model(.preparing):
            dictationStatus = nil
        case .model(.ready), .model(.failed), .held, .error:
            if statusHold == nil { dictationStatus = nil }
        case nil:
            break
        }
        statusReveal = nil
        isDictationWaiting = false
    }

    // internal for testability — the level entry point (also used by
    // `bind(microphone:)`). Ignored outside `.recording` so a late buffer can't
    // raise the meter after the cycle has returned to idle/processing.
    func apply(inputLevel level: Float) {
        guard state == .recording else { return }
        inputLevel = level
        isAudioFlowing = true
    }

    // internal for testability — drives `hasLastTranscript` from the session's
    // `lastTranscriptAvailable` publisher (planning 0019). Availability only —
    // the content stays in the session.
    func apply(hasLastTranscript available: Bool) {
        hasLastTranscript = available
    }

    // internal for testability — the streaming transcript entry point (also used by
    // `bind`), so a test can show the transcript panel without a live session.
    func apply(liveTranscript text: String) {
        liveTranscript = text
    }

    // internal for testability — the live text's visibility entry point (also used by `bind`).
    func apply(isLiveTextShown shown: Bool) {
        isLiveTextShown = shown
    }

    // internal for testability — the registrations entry point (also used by `bind`), so a
    // snapshot shows a failing shortcut without another app holding it.
    func apply(shortcutRegistrations registrations: [RiverShortcut: HotKeyRegistration]) {
        shortcutRegistrations = registrations
    }

    /// Whether any of River's shortcuts failed to register, so it does nothing.
    var isAnyShortcutFailing: Bool {
        shortcutRegistrations.values.contains { $0 != .registered }
    }

    // internal for testability — the model selection entry point (also used by
    // `bind(transcription:)`), so a snapshot can show a switch without loading a model.
    func apply(modelSelection selection: ModelSelection) {
        modelSelection = selection
    }

    // Production scheduler: a cancelable main-queue delay. Cancelling the returned token (by
    // reassignment) stops a pending fire.
    static let liveScheduler: TimerScheduler = { seconds, action in
        let work = DispatchWorkItem { MainActor.assumeIsolated { action() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        return AnyCancellable { work.cancel() }
    }
}
