import Combine
import Foundation
import Observation

/// Schedules AppState's timers: the error toast's auto-dismiss, and the status row's reveal and
/// hold (planning 0004). Injected so tests fire them synchronously instead of waiting on
/// wall-clock time (planning 0018 AC4; the injectable-clock pattern of `TapStateMachine`).
/// Returns a token whose cancellation stops a pending action — reassigning it (a newer error)
/// cancels the previous timer.
typealias TimerScheduler = @MainActor (_ after: TimeInterval, _ action: @escaping @MainActor () -> Void) -> AnyCancellable

/// What the row beside the indicator says (planning 0004).
enum DictationStatus: Equatable {
    /// The model's state while a dictation waits for it, then ready, or failed with the
    /// recording kept.
    case model(StatusRing.Phase)
    /// The app dictated into isn't in front: River typed nothing and holds the text.
    case held
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
    /// Transient HUD toast (planning 0018). Distinct from `errorMessage` (the
    /// lingering menu row): it auto-dismisses after `errorToastDurationSeconds` and
    /// clears on a fresh recording. The menu row is the record; the toast is the alert.
    private(set) var toast: ErrorToast?
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
    /// The status beside the indicator (planning 0004): the model's state when a dictation ends
    /// before the model is ready, or text River held. Nil while nothing shows.
    private(set) var dictationStatus: DictationStatus?
    /// Whether the status keeps the panel up once River is idle: a failed load or held text for
    /// 4 s after it shows, and a ready check until it has been revealed.
    private(set) var holdsPanel = false
    /// How far the model in use has downloaded, 0 to 1, for the status ring: while it downloads,
    /// and where a failed download stopped. Nil otherwise.
    private(set) var downloadFraction: Double?
    // Set by the session's `discards` signal, which arrives just before that
    // recording's `.idle`; consumed as the state leaves `.recording`.
    @ObservationIgnored private var isDiscardPending = false

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private let schedule: TimerScheduler
    @ObservationIgnored private var toastDismissal: AnyCancellable?
    // The status row's timers and what it has heard since the release: the dictation waits
    // for the model, or its recording was kept, and whether the half second has passed.
    @ObservationIgnored private var statusReveal: AnyCancellable?
    @ObservationIgnored private var statusHold: AnyCancellable?
    @ObservationIgnored private var isRevealDue = false
    @ObservationIgnored private var dictationWaits = false
    @ObservationIgnored private var recordingKept = false
    @ObservationIgnored private var downloadProgress: [String: Double] = [:]

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
            // A fresh recording clears a stale toast too (its lingering-record twin
            // stays on the menu row); its own auto-dismiss timer is now moot.
            toast = nil
            toastDismissal = nil
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
        // Graduate the same error into a transient HUD toast (planning 0018). The
        // toast is fixed copy per error *kind* — no user content — so it needs no
        // redaction; the redacted framework message stays on `errorMessage` only.
        // Reassigning `toastDismissal` cancels any previous pending dismiss, so the
        // newest error owns the timer.
        toast = ErrorToastPresentation.toast(for: error)
        toastDismissal = schedule(Constants.errorToastDurationSeconds) { [weak self] in
            self?.dismissToast()
        }
    }

    // internal for testability — the model load state entry point (also used by
    // `bind(transcription:)`). Drives the menu bar's download/load/ready label, and the status
    // row: a wait follows the model through preparing to ready, and a failure shown ends early
    // once the model loads after all.
    func apply(modelLoadState: ModelLoadState) {
        self.modelLoadState = modelLoadState
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
            dictationWaits = true
            showWaitIfDue()
        case .recordingKept:
            recordingKept = true
            // The panel stays up for the failure, even when River is idle before it shows.
            holdsPanel = true
            if dictationStatus != nil { show(.model(.failed)) } else { showWaitIfDue() }
        case .textHeld:
            show(.held)
        }
    }

    // internal for testability — each model's download fraction (also used by
    // `bind(transcription:)`); the row reads the model in use's.
    func apply(downloadProgress progress: [String: Double]) {
        downloadProgress = progress
        downloadFraction = progress[modelSelection.inUse]
    }

    // A fresh dictation starts with nothing beside the indicator.
    private func clearStatus() {
        dictationStatus = nil
        holdsPanel = false
        statusReveal = nil
        statusHold = nil
        isRevealDue = false
        dictationWaits = false
        recordingKept = false
    }

    // The row appears half a second after the release, and only if the dictation still waits
    // for the model then: a load that finishes sooner shows nothing.
    private func scheduleReveal() {
        clearStatus()
        statusReveal = schedule(Constants.statusRevealDelaySeconds) { [weak self] in
            guard let self else { return }
            self.statusReveal = nil
            self.isRevealDue = true
            self.showWaitIfDue()
        }
    }

    private func showWaitIfDue() {
        guard isRevealDue, dictationStatus == nil else { return }
        if recordingKept {
            // The model loaded after all before the row showed: there is nothing to say.
            if modelLoadState == .ready { endHold() } else { show(.model(.failed)) }
        } else if dictationWaits, state == .processing, let phase = waitingPhase {
            show(.model(phase))
        }
    }

    // The model's phase while a dictation waits for it: nil once it is ready or has failed.
    private var waitingPhase: StatusRing.Phase? {
        switch modelLoadState {
        case .downloading: .downloading
        case .loading: .preparing
        case .ready, .failed: nil
        }
    }

    private func show(_ status: DictationStatus) {
        dictationStatus = status
        // Once something shows, the reveal still to come has nothing to add.
        statusReveal = nil
        switch status {
        case .model(.failed), .held:
            holdsPanel = true
            statusHold = schedule(Constants.statusHoldSeconds) { [weak self] in self?.endHold() }
        case .model(.ready):
            // Until the check has been revealed, so the panel never leaves with it half drawn.
            holdsPanel = true
            statusHold = schedule(Constants.statusRingCheckDelaySeconds + Constants.statusRingCheckSeconds) { [weak self] in
                self?.endHold()
            }
        case .model(.downloading), .model(.preparing):
            break
        }
    }

    private func endHold() {
        statusHold = nil
        holdsPanel = false
        recordingKept = false
        if state == .idle { dictationStatus = nil }
    }

    // Back at idle: a wait that ended without the model (Cancel Dictation) goes with the cycle,
    // and so does a reveal still to come, unless a kept recording waits on it. A hold runs on.
    private func settleStatus() {
        switch dictationStatus {
        case .model(.downloading), .model(.preparing):
            dictationStatus = nil
            statusReveal = nil
        case .model(.ready):
            if statusHold == nil { dictationStatus = nil }
        case .model(.failed), .held:
            break
        case nil:
            if !recordingKept { statusReveal = nil }
        }
        dictationWaits = false
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
        downloadFraction = downloadProgress[selection.inUse]
    }

    // internal for testability — clears the toast when its timer fires. Separate so
    // the scheduled closure has a named target and the fired-clear is observable.
    func dismissToast() {
        toast = nil
        toastDismissal = nil
    }

    // Production scheduler: a cancelable main-queue delay. Cancelling the returned token (via
    // reassignment or `dismissToast`) stops a pending fire.
    static let liveScheduler: TimerScheduler = { seconds, action in
        let work = DispatchWorkItem { MainActor.assumeIsolated { action() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        return AnyCancellable { work.cancel() }
    }
}
