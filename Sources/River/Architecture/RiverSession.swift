import AppKit
import Combine
import Foundation
import os

// Cycle-failure surface, one case per stage; redact the message before display (ADR 0002).
enum RiverError: LocalizedError {
    case audioCapture(underlying: Error)
    case transcription(underlying: Error)
    case textInsertion(underlying: Error)
    /// A required permission is known-denied, so the cycle was refused before any
    /// audio was captured (planning 0012 AC5). Carries the capability's display
    /// name rather than an underlying error — nothing failed, the attempt was
    /// declined up front.
    case permission(capability: String)

    var errorDescription: String? {
        switch self {
        case .audioCapture(let underlying): return "Couldn't capture audio: \(underlying.localizedDescription)"
        case .transcription(let underlying): return "Couldn't transcribe: \(underlying.localizedDescription)"
        case .textInsertion(let underlying): return "Couldn't paste: \(underlying.localizedDescription)"
        case .permission(let capability): return "\(capability) permission is needed to dictate."
        }
    }
}

@MainActor
final class RiverSession {
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "app")
    private let stateSubject = CurrentValueSubject<RiverState, Never>(.idle)
    private let errorSubject = PassthroughSubject<RiverError, Never>()
    private let noticeSubject = PassthroughSubject<String, Never>()
    private let discardSubject = PassthroughSubject<Void, Never>()
    private let eventSubject = PassthroughSubject<DictationEvent, Never>()

    private let accessibility: AccessibilityCapability
    private let microphone: MicrophoneCapability
    private let inputMonitoring: InputMonitoringCapability
    private let hotkey: HotkeyManager
    private let audio: AudioCaptureManager
    private let textInsertion: TextInsertionManager
    private let transcription: TranscriptionManager
    private let settings: SettingsStore
    private let system: SystemAvailabilityMonitor

    // The most recent successful transcription, retained in memory for user-initiated
    // recovery (planning 0019). Set on transcription success — including when the paste
    // then fails, which is the recovery case (AC1). Never persisted, never logged.
    // `didSet` keeps the availability subject in sync.
    private var lastTranscript: String? {
        didSet { lastTranscriptAvailableSubject.send(lastTranscript != nil) }
    }
    private let lastTranscriptAvailableSubject = CurrentValueSubject<Bool, Never>(false)

    // Recordings a failed load kept, in order, for the next load that succeeds (planning 0004).
    // Memory only, like `lastTranscript`: a quit loses them. Never logged.
    private var keptRecordings: [[Float]] = [] {
        didSet { keptCountSubject.send(keptRecordings.count) }
    }
    private let keptCountSubject = CurrentValueSubject<Int, Never>(0)
    // The wait of a dictation that ended before the model was ready; Cancel Dictation ends it.
    private var modelWait: Task<Void, Error>?
    // The kept recordings' decode, which runs at `.idle`. A dictation's own decodes wait for it,
    // so the engine runs one decode at a time.
    private var keptDecode: Task<Void, Never>?

    // The recording's live transcription when streaming is on (0025 prototype); nil otherwise.
    private var stream: DictationStream?
    // The text transcribed so far for the transcript panel. Unlike `lastTranscript` this
    // content does reach the UI layer: showing it is the point. Still never logged.
    private let liveTranscriptSubject = CurrentValueSubject<String, Never>("")
    // Whether this dictation's live text may show: only one that started with the model ready.
    private let liveTextAllowedSubject = CurrentValueSubject<Bool, Never>(true)

    private var isStarted = false
    private var cancellables = Set<AnyCancellable>()
    // A list, not a single slot: two settings (key + mode) can both be deferred
    // during one Hold recording or `.processing` window, and both must apply on
    // the return to `.idle` — a single slot would drop the earlier one.
    private var pendingReconfigurations: [() -> Void] = []
    // The mode driving the current recording — decides whether a mid-recording
    // key/mode change applies live (tap modes) or is deferred (Hold).
    private var activeMode: ActivationMode = Constants.defaultActivationMode

    // internal for testability — tests assert subscription wiring through the
    // counters rather than inspecting the handler closures.
    private(set) var configurationApplyCount = 0
    private(set) var configurationDeferCount = 0

    var state: AnyPublisher<RiverState, Never> { stateSubject.eraseToAnyPublisher() }
    var currentState: RiverState { stateSubject.value }
    // The cycle-failure surface for the menu bar (and, later, the recording HUD
    // — planning 0002). Lands with a renderer per river-pipeline.md.
    var errors: AnyPublisher<RiverError, Never> { errorSubject.eraseToAnyPublisher() }
    // Recording-context notices (e.g. "activation key changed — press it to stop").
    // Same observers as `errors`; shown in the menu bar now, the HUD later.
    var notices: AnyPublisher<String, Never> { noticeSubject.eraseToAnyPublisher() }
    // Fires just before a silent discard's `.idle`, so `AppState` can tell it from a
    // cancel, which looks the same as a state change.
    var discards: AnyPublisher<Void, Never> { discardSubject.eraseToAnyPublisher() }
    // What became of a dictation that ended before the model was ready, sent before `.idle`
    // so the panel can show it (planning 0004).
    var dictationEvents: AnyPublisher<DictationEvent, Never> { eventSubject.eraseToAnyPublisher() }
    // How many recordings a failed load kept, for Settings' "1 recording kept".
    var keptRecordingCount: AnyPublisher<Int, Never> { keptCountSubject.eraseToAnyPublisher() }
    // internal for testability — the count only, never the audio.
    var currentKeptRecordingCount: Int { keptRecordings.count }
    // Availability signal for the "Copy Last Transcription" menu item (planning 0019).
    // Emits `true` after the first successful transcription; `AppState` bridges it.
    var lastTranscriptAvailable: AnyPublisher<Bool, Never> { lastTranscriptAvailableSubject.eraseToAnyPublisher() }
    // internal for testability — availability only, never the content.
    var hasLastTranscript: Bool { lastTranscript != nil }
    // The streaming transcript of the current recording, for the transcript panel.
    var liveTranscript: AnyPublisher<String, Never> { liveTranscriptSubject.eraseToAnyPublisher() }
    // Whether the live text shows above the indicator (planning 0034, decision 2). Never for a
    // dictation that started before the model was ready (planning 0004): it would sit empty
    // through the wait and take the mouse.
    var isLiveTextShown: AnyPublisher<Bool, Never> {
        settings.publisher(for: Settings.showLiveText)
            .combineLatest(liveTextAllowedSubject)
            .map { shown, allowed in shown && allowed }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    // What macOS said to each combination River holds, for Settings' "Not working" lines.
    var shortcutRegistrations: AnyPublisher<[RiverShortcut: HotKeyRegistration], Never> { hotkey.registrations }

    init(
        accessibility: AccessibilityCapability,
        microphone: MicrophoneCapability,
        inputMonitoring: InputMonitoringCapability,
        hotkey: HotkeyManager,
        audio: AudioCaptureManager,
        textInsertion: TextInsertionManager,
        transcription: TranscriptionManager,
        settings: SettingsStore,
        system: SystemAvailabilityMonitor
    ) {
        self.accessibility = accessibility
        self.microphone = microphone
        self.inputMonitoring = inputMonitoring
        self.hotkey = hotkey
        self.audio = audio
        self.textInsertion = textInsertion
        self.transcription = transcription
        self.settings = settings
        self.system = system
    }

    func start() async throws {
        guard !isStarted else { return }
        isStarted = true
        subscribeToConfiguration()
        subscribeToMicrophoneReadiness()
        wireHotkeyCallbacks()
        await hotkey.start()
        logger.info("RiverSession started")
    }

    func stop() async {
        guard isStarted else { return }
        isStarted = false
        await hotkey.stop()
        cancellables.removeAll()
        await audio.setReady(false)
        logger.info("RiverSession stopped")
    }

    /// Writes the last retained transcription to the general pasteboard (a test passes
    /// a private one). No-op when no transcription has been retained yet.
    ///
    /// User-initiated only — the automated insertion cycle never touches the
    /// clipboard (planning 0011). Applies nspasteboard.org marker types so
    /// well-behaved clipboard managers skip recording the dictated content.
    func copyLastTranscript(to pasteboard: NSPasteboard = .general) {
        guard let text = lastTranscript else { return }
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        for rawType in Constants.pasteboardMarkerTypes {
            item.setData(Data(), forType: NSPasteboard.PasteboardType(rawType))
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        // Content is never logged — only its count; see logging.md anti-pattern #4.
        logger.info("Copied last transcript to pasteboard (\(text.count, privacy: .public) chars)")
    }

    // internal for testability — wires hotkey callbacks without starting the
    // real tap, so tests can drive the chain via `InputMonitoringCapability.publishForTest`.
    func wireHotkeyCallbacks() {
        hotkey.onActivate = { [weak self] in self?.handleActivate() }
        hotkey.onDeactivate = { [weak self] in
            Task { @MainActor in await self?.handleDeactivate() }
        }
        hotkey.onCancel = { [weak self] in self?.handleCancel() }
        hotkey.onDiscard = { [weak self] in self?.handleDiscard() }
        hotkey.onPasteLast = { [weak self] in self?.pasteLastTranscript() }
        hotkey.onCopyLast = { [weak self] in self?.copyLastTranscript() }
        hotkey.onToggleLiveText = { [weak self] in self?.toggleLiveText() }
        hotkey.isRecording = { [weak self] in self?.currentState == .recording }
        // Esc cancels only while a recording runs; between recordings it belongs to the app
        // in front (spec 0036).
        stateSubject
            .map { $0 == .recording }
            .removeDuplicates()
            .sink { [weak self] recording in self?.hotkey.setRecording(recording) }
            .store(in: &cancellables)
        // The capture watchdog ends a recording whose audio stopped arriving, through the
        // same path as a key release; `stopRecording` reports the shortfall from there.
        audio.onCaptureGapExceeded = { [weak self] in
            Task { @MainActor in await self?.handleDeactivate() }
        }
    }

    // internal for testability — state-guarded `.idle` → `.recording` transition.
    // Audio capture is kicked off fire-and-forget so the state change is
    // immediately observable; engine-warmup race is handled at stop time.
    //
    // A model still downloading or getting ready doesn't stop a dictation (planning 0004):
    // it records, and waits for the model at release.
    func handleActivate() {
        guard currentState == .idle else {
            logger.info("Ignoring activate in state \(String(describing: self.currentState), privacy: .public)")
            return
        }
        // Pre-recording capability gate (planning 0012 AC5). Without this the app
        // accepts a full dictation it cannot possibly complete — the field log has a
        // 35-second recording captured while Accessibility was denied, which could
        // only die at paste time with the audio already gone. Declining up front
        // costs the user nothing; accepting costs them everything they just said.
        //
        // Only `.denied` blocks. `.unknown` proceeds, matching the fail-open posture
        // the insertion guard already uses (planning 0001): an uncertain reading must
        // never be the thing that stops a dictation.
        if let blocked = deniedRequiredCapability() {
            logger.info("Ignoring activate: \(blocked, privacy: .public) is denied")
            errorSubject.send(.permission(capability: blocked))
            return
        }
        stateSubject.send(.recording)
        logger.info("State -> recording")
        liveTranscriptSubject.send("")
        liveTextAllowedSubject.send(transcription.currentModelLoadState == .ready)
        // Made even while the model isn't ready: its segments fail until it is, and it then
        // decodes from the first failed one in one piece at release.
        let stream = settings.value(for: Settings.streamingDictation) ? makeStream() : nil
        self.stream = stream
        let audio = self.audio
        Task { @MainActor in
            await audio.startRecording(onSamples: stream.map { stream in { stream.append($0) } })
        }
    }

    private func makeStream() -> DictationStream {
        let stream = DictationStream { [weak self] samples in
            guard let self else { throw CancellationError() }
            return try await self.transcribeInTurn(samples)
        }
        stream.onTextChange = { [weak self] text in self?.liveTranscriptSubject.send(text) }
        stream.showsPreview = settings.value(for: Settings.showLiveText)
        return stream
    }

    // internal for testability — full cycle: `.recording` → `.processing` →
    // capture/convert/transcribe/paste → `.idle`. Async so tests can `await`
    // the complete cycle. Each step's failure is caught independently so the
    // cycle always returns to `.idle` and pending reconfiguration applies;
    // getting stuck in `.processing` would freeze the app (river-pipeline.md).
    // A model not yet ready is waited for in `.processing` (`waitForModel`).
    func handleDeactivate() async {
        guard currentState == .recording else {
            logger.info("Ignoring deactivate in state \(String(describing: self.currentState), privacy: .public)")
            return
        }
        stateSubject.send(.processing)
        logger.info("State -> processing")
        // Every way out returns to `.idle`: a failed load and Cancel Dictation end it early.
        defer { returnToIdle() }
        let stream = self.stream
        self.stream = nil
        let released = ContinuousClock.now
        do {
            let samples = try await audio.stopRecording()
            logger.info("Captured \(samples.count, privacy: .public) samples")
            if let stream, stream.cutCount > 0 {
                guard await waitForModel(keeping: samples) else {
                    stream.cancel()
                    return
                }
                // Streaming: the segments are already decoded; only the tail is left.
                let outcome = await stream.finish()
                logger.info("Streamed \(stream.cutCount, privacy: .public) segments, \(stream.provisionalCount, privacy: .public) provisional; release-to-text \(String(format: "%.2f", Self.seconds(since: released)), privacy: .public) s with \(self.transcription.currentModelName, privacy: .public)")
                if let error = outcome.error {
                    errorSubject.send(.transcription(underlying: error))
                }
                if outcome.text.isEmpty {
                    logger.info("Stream found no speech; skipping paste")
                } else {
                    liveTranscriptSubject.send(outcome.text)
                    await deliver(outcome.text)
                }
            } else if samples.isEmpty {
                stream?.cancel()
                // Buffers arrived but the silence trim removed everything: an
                // all-silence recording (a stray key-brush, an accidental tap). The
                // user said nothing — NOT a failure. Drop silently: don't decode
                // (Whisper hallucinates text from silence), don't paste, don't raise
                // the error glyph. The `notices` channel clears on recording-end
                // (AppState) so a post-recording message wouldn't survive there, and
                // a stray brush shouldn't nag; logged for observability (planning
                // 0023). A recording that DID contain speech but decoded empty still
                // throws `.emptyTranscription` below and surfaces loudly.
                logger.info("Recording was all silence after trim; skipping decode")
            } else {
                // No pause long enough to cut (or streaming off): the one-shot decode,
                // after any provisional decode still running, so the two never overlap.
                if let stream {
                    await stream.cancelAndWait()
                    logger.info("Stream made no cut (\(stream.provisionalCount, privacy: .public) provisional); decoding in one piece")
                }
                guard await waitForModel(keeping: samples) else { return }
                do {
                    let text = try await transcribeInTurn(samples)
                    logger.info("Transcribed \(text.count, privacy: .public) chars; release-to-text \(String(format: "%.2f", Self.seconds(since: released)), privacy: .public) s with \(self.transcription.currentModelName, privacy: .public)")
                    await deliver(text)
                } catch TranscriptionError.noSpeechDetected {
                    // Decode heard only non-speech (breath, room tone, music the
                    // trim didn't catch): same policy as the all-silence branch
                    // above — nothing was said, so no paste and no error glyph
                    // (planning 0023). When the 0002/0018/0020 feedback surface
                    // lands, it becomes the home for a friendly "no speech
                    // detected" notice; until then this is log-only.
                    logger.info("Decode found no speech; skipping paste")
                } catch {
                    logger.error("Transcription failed: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
                    errorSubject.send(.transcription(underlying: error))
                }
            }
        } catch {
            logger.error("Audio capture failed: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
            // Type what was heard (decided 2026-10-23): the stream decoded the audio that
            // did arrive, and discarding it would lose the user's words along with the
            // ones the microphone never delivered. The error follows the text. Not when no
            // live audio arrived: then the stream holds only the pre-roll, audio from before
            // the press, which is never typed on its own (planning 0033).
            if case AudioCaptureError.noAudioCaptured = error {
                stream?.cancel()
            } else if let stream {
                if await waitForModel(keeping: AudioCaptureManager.trimSilence(stream.samples)) {
                    let outcome = await stream.finish()
                    if !outcome.text.isEmpty {
                        logger.info("Typing the \(outcome.text.count, privacy: .public) chars heard before capture failed")
                        liveTranscriptSubject.send(outcome.text)
                        await deliver(outcome.text)
                    }
                } else {
                    stream.cancel()
                }
            }
            errorSubject.send(.audioCapture(underlying: error))
        }
    }

    // The end of `handleDeactivate`'s cycle, whichever way it ended.
    private func returnToIdle() {
        stateSubject.send(.idle)
        logger.info("State -> idle")
        applyPendingReconfigurations()
        // A model that became ready mid-cycle takes over now; a no-op unless one is ready.
        transcription.commitModelSwitch()
        transcribeKeptRecordings()
    }

    // Waits in `.processing` for a model still downloading or getting ready (planning 0004),
    // so a press meanwhile is ignored; `true` once it is ready to decode. `false` when the
    // dictation ends here: the load failed and `recording` is kept for the next load that
    // succeeds, or Cancel Dictation threw it away. A load that has already failed fails at once.
    private func waitForModel(keeping recording: [Float]) async -> Bool {
        let state = transcription.currentModelLoadState
        guard state != .ready else { return true }
        logger.info("Waiting for the model (\(String(describing: state), privacy: .public))")
        if state != .failed { eventSubject.send(.waitingForModel) }
        let transcription = self.transcription
        let wait = Task { try await transcription.waitUntilReady() }
        modelWait = wait
        defer { modelWait = nil }
        do {
            try await wait.value
            logger.info("Model ready; transcribing the dictation that waited")
            return true
        } catch TranscriptionError.modelLoadFailed {
            guard !recording.isEmpty else { return false }
            keptRecordings.append(recording)
            logger.info("Model failed to load; \(self.keptRecordings.count, privacy: .public) recordings kept")
            eventSubject.send(.recordingKept)
            return false
        } catch {
            logger.info("Dictation waiting for the model canceled")
            return false
        }
    }

    // A decode for the current dictation, after any kept recordings' decode still running.
    private func transcribeInTurn(_ samples: [Float]) async throws -> String {
        await keptDecode?.value
        return try await transcription.transcribe(audioSamples: samples)
    }

    // Transcribes the recordings a failed load kept, once the model is ready and River is idle
    // (planning 0004): one at a time, stopping when a dictation starts. The text is joined with
    // a space, since Paste last types it and a newline is Return, and held as the last
    // transcript, never typed. Idempotent; the work runs in a task, after the caller returns.
    private func transcribeKeptRecordings() {
        guard keptDecode == nil, !keptRecordings.isEmpty, currentState == .idle,
              transcription.currentModelLoadState == .ready else { return }
        keptDecode = Task { @MainActor [weak self] in
            guard let self else { return }
            var texts: [String] = []
            while let recording = self.keptRecordings.first, self.currentState == .idle,
                  self.transcription.currentModelLoadState == .ready {
                do {
                    texts.append(try await self.transcription.transcribe(audioSamples: recording))
                } catch TranscriptionError.noSpeechDetected, TranscriptionError.emptyTranscription {
                    self.logger.info("A kept recording held no speech")
                } catch {
                    self.logger.error("Kept recording failed to transcribe: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
                    self.errorSubject.send(.transcription(underlying: error))
                }
                self.keptRecordings.removeFirst()
            }
            if !texts.isEmpty {
                let text = texts.joined(separator: " ")
                self.lastTranscript = text
                self.logger.info("Held \(texts.count, privacy: .public) kept recordings as the last transcript (\(text.count, privacy: .public) chars)")
            }
            self.keptDecode = nil
        }
    }

    /// The menu's Cancel Dictation (planning 0004): throws away a dictation waiting for the
    /// model, and River returns to `.idle`. The model keeps loading. A no-op unless one waits.
    func cancelWaiting() {
        guard let modelWait else {
            logger.info("Ignoring cancel: no dictation is waiting for the model")
            return
        }
        logger.info("Cancel: discarding the dictation waiting for the model")
        modelWait.cancel()
    }

    // Retains the transcript, then types it at the cursor. Retained before the paste
    // attempt: recovery is available even when insertion fails (planning 0019 AC1).
    // Content is never logged — only its count is; see logging.md anti-pattern #4.
    private func deliver(_ text: String) async {
        lastTranscript = text
        do {
            try await textInsertion.insertText(text)
        } catch {
            logger.error("Text insertion failed: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
            errorSubject.send(.textInsertion(underlying: error))
        }
    }

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    // internal for testability — the first known-denied required capability, or nil
    // when none is. Order is the user-facing priority: Accessibility first, since a
    // denied paste is the failure that silently eats a whole dictation.
    //
    // Input Monitoring is deliberately NOT gated here: it is what delivers the
    // hotkey in the first place, so a denied Input Monitoring means `handleActivate`
    // is never called at all. Gating on it would be unreachable via the only path
    // that reaches this method, and would make the gate depend on live TCC state for
    // a capability whose failure mode is "nothing happens" rather than "audio lost."
    func deniedRequiredCapability() -> String? {
        let required: [any Capability] = [accessibility, microphone]
        return required.first { $0.currentStatus == .denied }?.displayName
    }

    // internal for testability — the discard transition (planning 0017):
    // `.recording → .idle` with NO transcription and NO paste. Guarded to
    // `.recording`, mirroring the re-entrancy posture of `handleActivate` /
    // `handleDeactivate`, so cancel while `.idle` or `.processing` is a logged
    // no-op (cancel during `.processing` is out of scope — the paste is imminent).
    // The audio buffers are discarded (never converted); a `notices` message makes
    // the cancel visible. Crucially it runs the SAME deferral loop as the normal
    // cycle end, so a key/mode/model change parked during the canceled recording
    // still applies on the return to `.idle` (AC3). The notice is sent AFTER the
    // `.idle` transition: `AppState` clears recording-context notices on leaving
    // `.recording`, so emitting first would immediately wipe it.
    func handleCancel() {
        guard currentState == .recording else {
            logger.info("Ignoring cancel in state \(String(describing: self.currentState), privacy: .public)")
            return
        }
        logger.info("Cancel: discarding in-flight recording (no transcription, no paste)")
        stream?.cancel()
        stream = nil
        liveTranscriptSubject.send("")
        let audio = self.audio
        Task { @MainActor in await audio.discardRecording() }
        stateSubject.send(.idle)
        logger.info("State -> idle (canceled)")
        noticeSubject.send(ActivationNotice.recordingCanceled)
        applyPendingReconfigurations()
        // A model that became ready mid-cycle takes over now; a no-op unless one is ready.
        transcription.commitModelSwitch()
        transcribeKeptRecordings()
    }

    // internal for testability — a recording thrown away because the held dictation
    // modifier turned out to be part of another River shortcut (spec 0036). The same
    // `.recording → .idle` discard as `handleCancel`, but silent: the user never meant
    // to dictate, so there is no notice, and the `discarded` signal sent before
    // `.idle` tells `AppState` to play no cue.
    func handleDiscard() {
        guard currentState == .recording else {
            logger.info("Ignoring discard in state \(String(describing: self.currentState), privacy: .public)")
            return
        }
        logger.info("Discard: another shortcut used the dictation key (no transcription, no paste, no cue)")
        stream?.cancel()
        stream = nil
        liveTranscriptSubject.send("")
        let audio = self.audio
        Task { @MainActor in await audio.discardRecording() }
        discardSubject.send()
        stateSubject.send(.idle)
        logger.info("State -> idle (discarded)")
        applyPendingReconfigurations()
        // A model that became ready mid-cycle takes over now; a no-op unless one is ready.
        transcription.commitModelSwitch()
        transcribeKeptRecordings()
    }

    // Pending reconfigurations parked during a non-idle cycle fire on the
    // return to `.idle` — closes the deferral loop documented in
    // `architecture/river-session.md` "Reconfiguration without leaks".
    private func applyPendingReconfigurations() {
        guard !pendingReconfigurations.isEmpty else { return }
        let pending = pendingReconfigurations
        pendingReconfigurations.removeAll()
        for apply in pending {
            apply()
            configurationApplyCount += 1
        }
    }

    // Subscribes to the activation publishers. Each change routes through
    // `reconfigureHotkey`, which applies live, defers, or notifies depending on
    // the cycle state and active mode.
    private func subscribeToConfiguration() {
        settings.publisher(for: Settings.dictationShortcut)
            .sink { [weak self] newShortcut in
                self?.reconfigureHotkey(notice: ActivationNotice.keyChanged(to: newShortcut)) { [weak self] in
                    self?.hotkey.setShortcut(newShortcut)
                }
            }
            .store(in: &cancellables)
        // Paste last's and Copy last's shortcuts apply at once (spec 0036, Changes apply).
        settings.publisher(for: Settings.pasteLastShortcut)
            .sink { [weak self] value in self?.hotkey.setShortcut(value, for: .pasteLast) }
            .store(in: &cancellables)
        settings.publisher(for: Settings.copyLastShortcut)
            .sink { [weak self] value in self?.hotkey.setShortcut(value, for: .copyLast) }
            .store(in: &cancellables)
        settings.publisher(for: Settings.liveTextShortcut)
            .sink { [weak self] value in self?.hotkey.setShortcut(value, for: .toggleLiveText) }
            .store(in: &cancellables)
        // Hidden, a recording runs no preview decodes; shown again, it runs them on their own
        // schedule (planning 0034, decision 3).
        settings.publisher(for: Settings.showLiveText)
            .sink { [weak self] shown in self?.stream?.showsPreview = shown }
            .store(in: &cancellables)
        settings.publisher(for: Settings.activationMode)
            .sink { [weak self] newMode in
                self?.reconfigureHotkey(notice: ActivationNotice.modeChanged(to: newMode)) { [weak self] in
                    self?.hotkey.setActivationMode(newMode)
                    self?.activeMode = newMode
                }
            }
            .store(in: &cancellables)
        transcription.selection
            .sink { [weak self] selection in
                guard let self else { return }
                // `selectedModel` records the model in use once it is ready, so a relaunch
                // loads one that worked; it is written here only, and read only at launch.
                if selection.inUseState == .ready,
                   self.settings.value(for: Settings.selectedModel) != selection.inUse {
                    self.settings.setValue(selection.inUse, for: Settings.selectedModel)
                }
                // A model ready beside the one in use takes over at `.idle`; one that becomes
                // ready mid-cycle takes over on the return to `.idle`. The commit waits until
                // this value has reached every subscriber: committing inside the delivery sends
                // the switched selection first, and the rest then receive this older one last,
                // which left the Model section reading "Waiting" after the switch (PR 7a smoke).
                if selection.next?.phase == .ready, self.currentState == .idle {
                    Task { @MainActor [weak self] in
                        guard let self, self.currentState == .idle else { return }
                        self.transcription.commitModelSwitch()
                    }
                }
                // Recordings a failed load kept are transcribed once a model is ready at `.idle`.
                if selection.inUseState == .ready { self.transcribeKeptRecordings() }
            }
            .store(in: &cancellables)
    }

    /// The Settings recorder's pause (spec 0036, The recorder): River's shortcuts stop while
    /// it listens, so it sees the keys they would take. Refused unless idle, since a dictation
    /// needs its shortcut to stop. Returns whether the shortcuts are paused.
    func pauseShortcuts() -> Bool {
        guard currentState == .idle else { return false }
        hotkey.pause()
        return true
    }

    /// Brings River's shortcuts back once every modifier key is up (`HotkeyManager.resume`).
    func resumeShortcuts() {
        hotkey.resume()
    }

    /// Whether `shortcut` can be `row`'s shortcut, and if not, why
    /// (`HotkeyManager.availability(of:for:)`).
    func availability(of shortcut: Shortcut, for row: RiverShortcut) -> ShortcutAvailability {
        hotkey.availability(of: shortcut, for: row)
    }

    /// Toggle live text's shortcut (planning 0034): shows or hides the live text, during a
    /// recording or between recordings, and the choice is kept for the next one.
    func toggleLiveText() {
        let shown = !settings.value(for: Settings.showLiveText)
        logger.info("Live text \(shown ? "shown" : "hidden", privacy: .public)")
        if shown, !settings.value(for: Settings.streamingDictation) {
            // The hidden fallback decodes at release only, so there is no text to show.
            logger.notice("Live text has nothing to show: streamingDictation is off (defaults delete com.river.app streamingDictation)")
        }
        settings.setValue(shown, for: Settings.showLiveText)
    }

    /// Paste last transcription's shortcut (spec 0036): types the last transcription again at
    /// the cursor through the same insertion path, so the clipboard is never touched. Does
    /// nothing with no transcription yet, or while a dictation is recording or processing.
    func pasteLastTranscript() {
        guard currentState == .idle, let text = lastTranscript else {
            logger.info("Paste last ignored in state \(String(describing: self.currentState), privacy: .public)")
            return
        }
        logger.info("Pasting the last transcript again (\(text.count, privacy: .public) chars)")
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.textInsertion.insertText(text)
            } catch {
                self.logger.error("Text insertion failed: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
                self.errorSubject.send(.textInsertion(underlying: error))
            }
        }
    }

    /// The Model section's Select and Try Again (planning 0036): makes `name` the model River
    /// uses. It starts loading at once, even mid-dictation. Beside a ready model it takes over
    /// only at `.idle`, so no recording changes model halfway; with no ready model it replaces
    /// the one loading, and a dictation waiting for a model waits for it. Choosing the model in
    /// use retries it after a failure, or drops a model loading beside it.
    func selectModel(_ name: String) {
        let transcription = self.transcription
        Task { @MainActor in await transcription.switchModel(to: name) }
    }

    /// The Model section's Delete model (planning 0038): deletes a downloaded model's files.
    /// `TranscriptionManager` refuses the model in use and one loading beside it.
    func deleteModel(_ name: String) throws {
        try transcription.deleteModel(named: name)
    }

    // The ready microphone (planning 0033, decision 5): the capture unit runs between
    // recordings only while a dictation is possible. The inputs are combined here and
    // the pure rule decides; `AudioCaptureManager` owns the unit and applies a change
    // that lands mid-recording when the recording ends, so this does not go through
    // `reconfigureHotkey`'s apply-or-defer path. Onboarding is complete when all three
    // permissions are granted, the same three `AppDelegate` hands to onboarding.
    private func subscribeToMicrophoneReadiness() {
        let onboardingComplete = accessibility.status
            .combineLatest(microphone.status, inputMonitoring.status)
            .map { !OnboardingGate.shouldPresent(statuses: [$0, $1, $2]) }
        settings.publisher(for: Settings.keepMicrophoneReady)
            .combineLatest(onboardingComplete, system.availability)
            .map { keepReady, onboardingComplete, system in
                MicrophoneReadiness.shouldListen(
                    keepMicrophoneReady: keepReady, onboardingComplete: onboardingComplete, system: system
                )
            }
            .removeDuplicates()
            .sink { [weak self] ready in
                guard let self else { return }
                let audio = self.audio
                Task { @MainActor in await audio.setReady(ready) }
            }
            .store(in: &cancellables)
    }

    // Mode-dependent reconfiguration. Idle applies immediately. During a tap-mode
    // recording the change applies LIVE and the user is notified — switching the
    // key is a keycode refilter, not a tap teardown, so the running tap and the
    // captured audio both survive, and the new key/mode is the stop gesture the
    // user just chose. A Hold recording (the user is holding the old key, whose
    // release must stay watched) and any `.processing` state defer to the next
    // return to `.idle`. See architecture/river-session.md.
    private func reconfigureHotkey(notice: @autoclosure () -> String, _ apply: @escaping () -> Void) {
        switch currentState {
        case .idle:
            apply()
            configurationApplyCount += 1
        case .recording where activeMode != .hold:
            apply()
            configurationApplyCount += 1
            noticeSubject.send(notice())
        case .recording, .processing:
            pendingReconfigurations.append(apply)
            configurationDeferCount += 1
        }
    }
}
