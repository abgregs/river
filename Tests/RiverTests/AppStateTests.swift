import Combine
import Foundation
import Testing
@testable import River

@Suite("AppState")
struct AppStateTests {
    @MainActor
    @Test("state changes propagate to the observable")
    func stateChangesPropagate() {
        let appState = AppState()
        #expect(appState.state == .idle)
        appState.apply(.recording)
        #expect(appState.state == .recording)
    }

    @MainActor
    @Test("a cycle error becomes a path-redacted message")
    func errorBecomesRedactedMessage() throws {
        // The single choke point: a framework error naming a home path must not
        // carry the account name onto the menu (ADR 0002). If this regresses,
        // the username ships in a screenshot of the menu.
        let appState = AppState()
        let underlying = NSError(
            domain: "WhisperKit", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "load failed at /Users/alice/Documents/model.bin"]
        )
        appState.apply(RiverError.transcription(underlying: underlying))
        let message = try #require(appState.errorMessage)
        #expect(message.contains("/Users/<user>/Documents/model.bin"))
        #expect(!message.contains("/Users/alice"))
    }

    @MainActor
    @Test("starting a new recording clears a stale error")
    func recordingClearsStaleError() {
        let appState = AppState()
        appState.apply(RiverError.textInsertion(underlying: NSError(domain: "x", code: 1)))
        #expect(appState.errorMessage != nil)
        appState.apply(.recording)
        #expect(appState.errorMessage == nil)
    }

    @MainActor
    @Test("a recording-context notice shows during recording and clears when it ends")
    func noticeShownThenClearedOnRecordingEnd() {
        // The live-apply notice is tied to the current recording — it must vanish
        // the moment that recording ends, not linger into the next cycle.
        let appState = AppState()
        appState.apply(.recording)
        appState.apply(notice: "Activation key changed to Left Control. Press it to stop the current recording.")
        #expect(appState.notice != nil)
        appState.apply(.processing)
        #expect(appState.notice == nil)
    }

    @MainActor
    @Test("a notice left by a canceled recording never rides into the next one")
    func canceledNoticeClearedByNextRecording() {
        // `handleCancel` sends `.idle` and *then* the cancel notice, so the
        // clear-on-leaving-recording above fires before the notice even arrives. Without
        // a clear on the way in, the next recording opened showing "Recording canceled."
        // (the 0017 bleed, seen in the maintainer's smoke 2026-09-17).
        let appState = AppState()
        appState.apply(.recording)
        appState.apply(.idle)
        appState.apply(notice: ActivationNotice.recordingCanceled)
        #expect(appState.notice == ActivationNotice.recordingCanceled)
        appState.apply(.recording)
        #expect(appState.notice == nil)
    }

    @MainActor
    @Test("a recording that goes straight to idle is recorded as canceled; one that passes processing is not")
    func lastRecordingWasCanceledTracksHowTheRecordingEnded() {
        // The sound cues read this to tell a cancel from a stopped all-silence
        // recording, whose `.processing` can pass before they observe the state
        // (planning 0023). Each recording overwrites the previous answer, so a cancel
        // cannot leak its cancel cue into the next, stopped recording.
        let appState = AppState()
        appState.apply(.recording)
        appState.apply(.idle)                     // canceled (planning 0017)
        #expect(appState.lastRecordingWasCanceled)

        appState.apply(.recording)
        appState.apply(.processing)               // stopped
        appState.apply(.idle)
        #expect(!appState.lastRecordingWasCanceled)
    }

    @MainActor
    @Test("a discarded recording is recorded as discarded, not canceled, for that recording only")
    func lastRecordingWasDiscardedTracksOneRecording() {
        // The cues read this to stay silent for a discard (spec 0036). A discard that
        // read as a cancel would play the cancel cue; one that leaked into the next
        // recording would silence a real cancel.
        let appState = AppState()
        appState.apply(.recording)
        appState.applyDiscard()
        appState.apply(.idle)
        #expect(appState.lastRecordingWasDiscarded)
        #expect(!appState.lastRecordingWasCanceled)

        appState.apply(.recording)
        appState.apply(.idle)                     // a real cancel
        #expect(!appState.lastRecordingWasDiscarded)
        #expect(appState.lastRecordingWasCanceled)
    }

    @MainActor
    @Test("bind(to:) wires state, notices, and errors from a real session end to end")
    func bindWiresAllThreeChannels() async throws {
        // `apply(_:)` is unit-tested above, but nothing asserts `bind` actually
        // connects the three publishers. A dropped `.sink` or a mis-wired
        // publisher would pass every `apply` test while the menu silently stops
        // updating. Drive a real `RiverSession` cycle and assert all three
        // observable properties track — including the notice's clear-on-end.
        let env = makeBoundEnv()
        try await env.session.start()
        env.store.setValue(ActivationMode.singleTap, for: Settings.activationMode)  // activeMode → tap

        env.session.handleActivate()                       // → .recording (state channel)
        #expect(env.appState.state == .recording)

        env.store.setValue(.modifier(keyCode: 59), for: Settings.dictationShortcut)  // live tap-mode change → notice channel
        #expect(env.appState.notice != nil)

        await env.session.handleDeactivate()               // no buffer → .audioCapture (error channel)
        #expect(env.appState.state == .idle)               // state tracked through the whole cycle
        #expect(env.appState.errorMessage != nil)          // the cycle error reached the observable
        #expect(env.appState.notice == nil)                // notice cleared when the recording ended
    }

    @MainActor
    @Test("model load state propagates through apply(modelLoadState:)")
    func modelLoadStateApply() {
        // planning 0004: the load state entry point drives the menu bar's
        // download/load/ready label independently of the cycle state.
        let appState = AppState()
        #expect(appState.modelLoadState == .loading)  // default before bind
        appState.apply(modelLoadState: .downloading)
        #expect(appState.modelLoadState == .downloading)
        appState.apply(modelLoadState: .ready)
        #expect(appState.modelLoadState == .ready)
    }

    @MainActor
    @Test("bind(transcription:) wires model load state from the real publisher")
    func bindTranscriptionWiresModelLoadState() {
        let transcription = TranscriptionManager()
        let appState = AppState()
        appState.bind(transcription: transcription)

        // The bind subscribes to `modelLoadState` publisher via CurrentValueSubject,
        // which immediately delivers the current value on subscribe.
        let initialState = appState.modelLoadState
        // Should be .downloading or .loading depending on whether the model is
        // cached on this machine — either is valid, just not .ready or .failed.
        #expect(initialState == .downloading || initialState == .loading)

        // Driving via the test seam confirms the publisher → apply bridge is live.
        transcription.setModelLoadStateForTesting(.ready)
        #expect(appState.modelLoadState == .ready)
    }

    // MARK: - Error toast lifecycle (planning 0018)

    @MainActor
    @Test("a cycle error sets a transient toast alongside the lingering menu-row message")
    func errorSetsToast() {
        // Two renderers of one error (planning 0018): the redacted `errorMessage`
        // is the lingering menu record; the `toast` is the transient HUD alert.
        let appState = AppState()
        let error = RiverError.textInsertion(underlying: NSError(domain: "x", code: 1))
        appState.apply(error)
        #expect(appState.toast == ErrorToastPresentation.toast(for: error))
        #expect(appState.errorMessage != nil)
    }

    @MainActor
    @Test("the toast auto-clears when its scheduled timer fires (injectable clock)")
    func toastAutoClearsOnTimer() {
        // AC1/AC4: the toast auto-dismisses after a bounded duration. An injected
        // scheduler fires the dismiss synchronously — no wall-clock wait — and
        // confirms the duration passed is the configured one.
        let scheduler = ManualScheduler()
        let appState = AppState(schedule: scheduler.schedule)
        appState.apply(RiverError.audioCapture(underlying: NSError(domain: "x", code: 1)))
        #expect(appState.toast != nil)
        #expect(scheduler.lastDelay == Constants.errorToastDurationSeconds)
        scheduler.fire()
        #expect(appState.toast == nil)
    }

    @MainActor
    @Test("a fresh recording clears a lingering toast (its timer is moot)")
    func recordingClearsToast() {
        let appState = AppState()
        appState.apply(RiverError.transcription(underlying: NSError(domain: "x", code: 1)))
        #expect(appState.toast != nil)
        appState.apply(.recording)
        #expect(appState.toast == nil)
    }

    // MARK: - Input level (planning 0020)

    @MainActor
    @Test("input level is applied only during recording and resets when it ends")
    func inputLevelGatedByRecording() {
        // The meter is a *live-capture* signal. A level arriving while idle or
        // processing (a late buffer) must not raise the meter, and the meter must
        // sit at rest the moment the recording ends.
        let appState = AppState()
        appState.apply(inputLevel: 0.8)
        #expect(appState.inputLevel == 0)          // ignored while idle
        appState.apply(.recording)
        appState.apply(inputLevel: 0.8)
        #expect(appState.inputLevel == 0.8)        // tracked during recording
        appState.apply(.processing)
        #expect(appState.inputLevel == 0)          // reset when recording ends
    }

    @MainActor
    @Test("audio counts as flowing from the first level reading of a recording until it ends")
    func audioFlowingFollowsFirstLevel() {
        // The indicator starts its voice layer on this. If it turned true on `.recording`
        // alone, a dead microphone would look live; if it outlived the recording, the next
        // recording's layer would start before its microphone delivered anything.
        let appState = AppState()
        appState.apply(inputLevel: 0.5)
        #expect(!appState.isAudioFlowing)          // a late buffer while idle is not audio
        appState.apply(.recording)
        #expect(!appState.isAudioFlowing)          // recording, but nothing heard yet
        appState.apply(inputLevel: 0)
        #expect(appState.isAudioFlowing)           // silence is still audio arriving
        appState.apply(.processing)
        #expect(!appState.isAudioFlowing)
        appState.apply(.recording)
        #expect(!appState.isAudioFlowing)          // each recording waits for its own first reading
    }

    @MainActor
    @Test("bind(microphone:) forwards the mic's level publisher into the observable")
    func bindMicrophoneWiresLevel() {
        // Nothing else asserts `bind(microphone:)` actually connects the publisher;
        // a dropped sink would pass every `apply(inputLevel:)` test while the HUD
        // meter silently stays dead. Drive a real emission through the subscription.
        let mic = MicrophoneCapability(now: { 0 })
        let appState = AppState()
        appState.apply(.recording)
        appState.bind(microphone: mic)
        mic.emitLevel(rms: Constants.inputLevelReferenceRMS)  // → normalized 1.0
        #expect(appState.inputLevel == 1.0)
    }

    // MARK: - Test environment

    @MainActor
    private struct BoundEnv {
        let appState: AppState
        let session: RiverSession
        let store: SettingsStore
    }

    // A real session (fakes only at the untestable OS-call leaves — the mic
    // engine is skipped) bound to a real AppState, so the test exercises the
    // actual `bind` subscriptions rather than calling `apply` directly.
    @MainActor
    private func makeBoundEnv() -> BoundEnv {
        let accessibility = AccessibilityCapability()
        // Not Accessibility-trusted in a test process, so grant it explicitly or the
        // 0012 AC5 activation gate refuses the cycle this test drives end to end.
        accessibility.setStatusForTesting(.granted)
        // Granting it also unlocks the real `CGEvent.post` path, which must stay
        // stubbed in tests — the suite has no Accessibility grant to post with.
        accessibility.skipPostForTesting = true
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let inputMonitoring = InputMonitoringCapability()
        let hotKeys = HotKeyRegistry(calls: .inert)
        let hotkey = HotkeyManager(
            inputMonitoring: inputMonitoring, hotKeys: hotKeys, initialShortcut: .modifier(keyCode: 62)
        )
        let store = SettingsStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let transcription = TranscriptionManager()
        // Unit tests never load the real model — mark ready so a dictation
        // never waits for one.
        transcription.setModelLoadStateForTesting(.ready)
        let session = RiverSession(
            accessibility: accessibility,
            microphone: microphone,
            inputMonitoring: inputMonitoring,
            hotkey: hotkey,
            audio: AudioCaptureManager(microphone: microphone),
            // One app in front throughout: a switch of app would hold the text, not type it.
            textInsertion: TextInsertionManager(accessibility: accessibility, frontmostApp: { 1 }),
            transcription: transcription,
            settings: store,
            system: SystemAvailabilityMonitor()
        )
        let appState = AppState()
        appState.bind(to: session)
        return BoundEnv(appState: appState, session: session, store: store)
    }
}

// Captures each scheduled timer instead of dispatching it, so a test fires them synchronously
// and asserts their delays — the injectable-clock pattern (planning 0018 AC4). A cancelled timer
// leaves the list, as a cancelled dispatch never fires.
@MainActor
private final class ManualScheduler {
    private var timers: [(id: Int, delay: TimeInterval, action: @MainActor () -> Void)] = []
    private var nextID = 0

    var schedule: TimerScheduler {
        { [weak self] delay, action in
            guard let self else { return AnyCancellable {} }
            let id = self.nextID
            self.nextID += 1
            self.timers.append((id, delay, action))
            return AnyCancellable { [weak self] in
                MainActor.assumeIsolated { self?.timers.removeAll { $0.id == id } }
            }
        }
    }

    /// The delays of the timers still pending, oldest first.
    var pendingDelays: [TimeInterval] { timers.map(\.delay) }
    var lastDelay: TimeInterval? { timers.last?.delay }

    /// Fires the newest pending timer.
    func fire() { fire(timers.last?.id) }

    /// Fires the pending timer scheduled `delay` seconds out.
    func fire(after delay: TimeInterval) { fire(timers.first { abs($0.delay - delay) < 1e-9 }?.id) }

    private func fire(_ id: Int?) {
        guard let id, let index = timers.firstIndex(where: { $0.id == id }) else { return }
        timers.remove(at: index).action()
    }
}

@Suite("AppState dictation status")
@MainActor
struct AppStateDictationStatusTests {
    // planning 0004, round eleven's "On the mark": the row beside the indicator speaks only once
    // a dictation ends with the model not ready, half a second after; a failed load and held text
    // stay 4 s, then leave with the panel; the menu bar and Settings keep the state after that.
    private let checkSeconds = Constants.statusRingCheckDelaySeconds + Constants.statusRingCheckSeconds

    private func make(_ model: ModelLoadState) -> (AppState, ManualScheduler) {
        let timers = ManualScheduler()
        let state = AppState(schedule: timers.schedule)
        state.apply(modelLoadState: model)
        return (state, timers)
    }

    // A dictation that ended and waits for the model.
    private func waiting(_ model: ModelLoadState = .downloading) -> (AppState, ManualScheduler) {
        let (state, timers) = make(model)
        state.apply(.recording)
        state.apply(.processing)
        state.apply(dictationEvent: .waitingForModel)
        return (state, timers)
    }

    @Test("nothing shows at launch or while you speak, whatever the model is doing")
    func nothingWhileSpeaking() {
        let (state, timers) = make(.downloading)
        #expect(state.dictationStatus == nil)
        state.apply(.recording)
        state.apply(modelLoadState: .loading)
        #expect(state.dictationStatus == nil)
        #expect(!state.holdsPanel)
        #expect(timers.pendingDelays.isEmpty)
    }

    @Test("a dictation that ends before the model is ready shows its state half a second after, then follows it to ready")
    func waitShowsAfterHalfASecond() {
        let (state, timers) = waiting()
        #expect(state.dictationStatus == nil)
        #expect(timers.pendingDelays == [Constants.statusRevealDelaySeconds])
        timers.fire(after: Constants.statusRevealDelaySeconds)
        #expect(state.dictationStatus == .model(.downloading))
        state.apply(modelLoadState: .loading)
        #expect(state.dictationStatus == .model(.preparing))
        state.apply(modelLoadState: .ready)
        #expect(state.dictationStatus == .model(.ready))
        // The text types and River is idle, but the panel stays until the check is drawn.
        state.apply(.idle)
        #expect(state.holdsPanel)
        timers.fire(after: checkSeconds)
        #expect(!state.holdsPanel)
        #expect(state.dictationStatus == nil)
    }

    @Test("a model ready within the half second shows nothing: the text types as usual")
    func quickLoadShowsNothing() {
        let (state, timers) = waiting(.loading)
        state.apply(modelLoadState: .ready)
        state.apply(.idle)
        #expect(timers.pendingDelays.isEmpty)
        #expect(state.dictationStatus == nil)
        #expect(!state.holdsPanel)
    }

    @Test("a load that fails while the row shows turns it to failed, which stays 4 s after River is idle")
    func failureShowsAndHolds() {
        let (state, timers) = waiting()
        timers.fire(after: Constants.statusRevealDelaySeconds)
        state.apply(modelLoadState: .failed)
        state.apply(dictationEvent: .recordingKept)
        state.apply(.idle)
        #expect(state.dictationStatus == .model(.failed))
        #expect(state.holdsPanel)
        #expect(timers.pendingDelays == [Constants.statusHoldSeconds])
        timers.fire(after: Constants.statusHoldSeconds)
        #expect(state.dictationStatus == nil)
        #expect(!state.holdsPanel)
    }

    @Test("a failure shown ends early once the model loads after all")
    func failureEndsWhenReady() {
        let (state, timers) = waiting()
        timers.fire(after: Constants.statusRevealDelaySeconds)
        state.apply(modelLoadState: .failed)
        state.apply(dictationEvent: .recordingKept)
        state.apply(.idle)
        // Try Again: the failure stays through the new download, and goes once the model is ready.
        state.apply(modelLoadState: .downloading)
        #expect(state.dictationStatus == .model(.failed))
        state.apply(modelLoadState: .ready)
        #expect(state.dictationStatus == nil)
        #expect(!state.holdsPanel)
    }

    @Test("a load that failed while you spoke shows already failed half a second after, the panel held until then")
    func failedBeforeTheRelease() {
        let (state, timers) = make(.failed)
        state.apply(.recording)
        state.apply(.processing)
        state.apply(dictationEvent: .recordingKept)
        state.apply(.idle)
        #expect(state.dictationStatus == nil)
        #expect(state.holdsPanel)
        timers.fire(after: Constants.statusRevealDelaySeconds)
        #expect(state.dictationStatus == .model(.failed))
        #expect(timers.pendingDelays == [Constants.statusHoldSeconds])
    }

    @Test("held text shows at once and stays 4 s")
    func heldShowsAtOnce() {
        let (state, timers) = make(.ready)
        state.apply(.recording)
        state.apply(.processing)
        state.apply(dictationEvent: .textHeld)
        #expect(state.dictationStatus == .held)
        state.apply(.idle)
        #expect(state.holdsPanel)
        #expect(timers.pendingDelays == [Constants.statusHoldSeconds])
        timers.fire(after: Constants.statusHoldSeconds)
        #expect(state.dictationStatus == nil)
        #expect(!state.holdsPanel)
    }

    @Test("Cancel Dictation takes the row away with the panel")
    func cancelEndsTheRow() {
        let (state, timers) = waiting()
        timers.fire(after: Constants.statusRevealDelaySeconds)
        state.apply(.idle)
        #expect(state.dictationStatus == nil)
        #expect(!state.holdsPanel)
    }

    @Test("a new recording starts with nothing beside the indicator")
    func recordingClearsTheRow() {
        let (state, timers) = make(.ready)
        state.apply(.recording)
        state.apply(.processing)
        state.apply(dictationEvent: .textHeld)
        state.apply(.idle)
        state.apply(.recording)
        #expect(state.dictationStatus == nil)
        #expect(!state.holdsPanel)
        #expect(timers.pendingDelays.isEmpty)
    }

    @Test("a dictation waits from the session's word until the model is ready, its load fails, or it is cancelled")
    func waitingForTheMenu() {
        // The menu offers Cancel Dictation for exactly this span.
        let (state, _) = waiting()
        #expect(state.isDictationWaiting)
        state.apply(modelLoadState: .ready)
        #expect(state.isDictationWaiting)   // nothing showed yet: the wait ends with the text typed
        state.apply(.idle)
        #expect(!state.isDictationWaiting)
        let (failing, _) = waiting()
        failing.apply(dictationEvent: .recordingKept)
        #expect(!failing.isDictationWaiting)
    }

    @Test("the download fraction is the model in use's")
    func fractionOfTheModelInUse() {
        let (state, _) = make(.downloading)
        state.apply(modelSelection: ModelSelection(inUse: "a", inUseState: .downloading, next: nil))
        state.apply(downloadProgress: ["a": 0.4, "b": 0.9])
        #expect(state.downloadFraction == 0.4)
        state.apply(modelSelection: ModelSelection(inUse: "b", inUseState: .downloading, next: nil))
        #expect(state.downloadFraction == 0.9)
        state.apply(downloadProgress: [:])
        #expect(state.downloadFraction == nil)
    }
}

@Suite("AppState shortcut registrations")
@MainActor
struct AppStateShortcutRegistrationTests {
    @Test("a shortcut that failed to register is failing until it registers, whichever row it is")
    func registrationFailure() {
        // The Settings window's badge reads this. A lone modifier has no registration and never
        // fails this way.
        let state = AppState()
        #expect(!state.isAnyShortcutFailing)
        state.apply(shortcutRegistrations: [.dictate: .takenByAnotherApp])
        #expect(state.isAnyShortcutFailing)
        state.apply(shortcutRegistrations: [.dictate: .registered, .copyLast: .refused(-9868)])
        #expect(state.isAnyShortcutFailing)
        state.apply(shortcutRegistrations: [.dictate: .registered, .pasteLast: .registered])
        #expect(!state.isAnyShortcutFailing)
        state.apply(shortcutRegistrations: [:])
        #expect(!state.isAnyShortcutFailing)
    }
}
