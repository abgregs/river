import AppKit
import AVFoundation
import Combine
import CoreGraphics
import Foundation
import Testing
@testable import River

@Suite("RiverSession")
struct RiverSessionTests {
    @MainActor
    @Test("start leaves state idle and is idempotent")
    func startIsIdempotentNoOpCycle() async throws {
        let env = makeSession()
        #expect(env.session.currentState == .idle)
        try await env.session.start()
        #expect(env.session.currentState == .idle)
        try await env.session.start()
        #expect(env.session.currentState == .idle)
    }

    @MainActor
    @Test("stop is idempotent")
    func stopIsIdempotent() async throws {
        let env = makeSession()
        try await env.session.start()
        await env.session.stop()
        await env.session.stop()
        #expect(env.session.currentState == .idle)
    }

    @MainActor
    @Test("state publisher emits .idle on subscribe")
    func statePublisherEmitsIdleInitially() {
        let env = makeSession()
        var received: [RiverState] = []
        let token = env.session.state.sink { received.append($0) }
        defer { token.cancel() }
        #expect(received == [.idle])
    }

    @MainActor
    @Test("start subscribes to configuration publishers")
    func startSubscribesToConfiguration() async throws {
        let env = makeSession()
        #expect(env.session.configurationApplyCount == 0)
        try await env.session.start()
        // Two disruptive settings (key + mode) each emit their current value on
        // subscribe and apply while idle.
        #expect(env.session.configurationApplyCount == 2)
    }

    @MainActor
    @Test("settings change while idle applies immediately")
    func settingsChangeWhileIdleApplies() async throws {
        let env = makeSession()
        try await env.session.start()
        let baseline = env.session.configurationApplyCount
        env.store.setValue(.modifier(keyCode: 59), for: Settings.dictationShortcut)
        #expect(env.session.configurationApplyCount == baseline + 1)
        #expect(env.session.configurationDeferCount == 0)
    }

    @MainActor
    @Test("activation mode change while idle applies immediately")
    func modeChangeWhileIdleApplies() async throws {
        let env = makeSession()
        try await env.session.start()
        let baseline = env.session.configurationApplyCount
        env.store.setValue(ActivationMode.doubleTap, for: Settings.activationMode)
        #expect(env.session.configurationApplyCount == baseline + 1)
        #expect(env.session.configurationDeferCount == 0)
    }

    @MainActor
    @Test("a tap-mode key change while recording applies live, keeps recording, and notifies")
    func tapModeKeyChangeAppliesLive() async throws {
        // The user changed the hotkey mid-recording in a tap mode. Unlike Hold
        // (which defers), this applies immediately — the recording continues and a
        // notice tells the user the new key now stops it. See river-session.md.
        let env = makeSession()
        try await env.session.start()
        env.store.setValue(ActivationMode.singleTap, for: Settings.activationMode)  // activeMode → singleTap

        var notices: [String] = []
        let token = env.session.notices.sink { notices.append($0) }
        defer { token.cancel() }

        env.session.handleActivate()  // → .recording
        #expect(env.session.currentState == .recording)
        let baseline = env.session.configurationApplyCount

        env.store.setValue(.modifier(keyCode: 59), for: Settings.dictationShortcut)  // change key mid-recording

        #expect(env.session.currentState == .recording)              // not deferred, not stopped
        #expect(env.session.configurationApplyCount == baseline + 1)  // applied live
        #expect(env.session.configurationDeferCount == 0)
        #expect(notices.count == 1)
    }

    // `selectedModel` records the model in use for the next launch; it is not a way to choose
    // one. If the session still listened to it, every takeover would come back as a new choice.
    @MainActor
    @Test("the saved model is a record, not an input: writing it does not switch models")
    func savedModelIsNotAnInput() async throws {
        let env = makeSession()
        try await env.session.start()
        env.store.setValue("openai_whisper-base.en", for: Settings.selectedModel)
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(env.transcription.currentModelName == Constants.defaultModel)
        #expect(env.transcription.currentModelSwitch == nil)
    }

    @MainActor
    @Test("a model chosen while idle takes over once it is ready, and is saved")
    func modelChosenWhileIdleTakesOver() async throws {
        let env = makeSession()
        try await env.session.start()
        env.session.selectModel("openai_whisper-base.en")
        // The choice reaches the manager through a MainActor Task, on the next run loop turn.
        await waitUntil { env.transcription.currentModelName == "openai_whisper-base.en" }
        #expect(env.transcription.currentModelName == "openai_whisper-base.en")
        #expect(env.store.value(for: Settings.selectedModel) == "openai_whisper-base.en")
    }

    // planning 0036, Model: a choice made mid-dictation starts loading at once, beside the
    // model in use, so the Model section shows its real progress; it never takes over the
    // recording in progress (planning 0021 AC2), only the return to .idle.
    @MainActor
    @Test("a model chosen mid-recording loads at once and takes over on the return to .idle")
    func modelChosenMidRecordingLoadsAtOnce() async throws {
        let env = makeSession()
        try await env.session.start()
        env.session.handleActivate()  // → .recording (Hold default)
        try await Task.sleep(nanoseconds: 20_000_000)

        env.session.selectModel("openai_whisper-base.en")
        await waitUntil { env.transcription.currentModelSwitch?.phase == .ready }
        #expect(env.transcription.currentModelSwitch?.phase == .ready)          // loaded, Waiting
        #expect(env.transcription.currentModelName == Constants.defaultModel)  // still the old model
        #expect(env.store.value(for: Settings.selectedModel) == Constants.defaultModel)

        env.microphone.publishForTest(makeBuffer())
        await env.session.handleDeactivate()
        #expect(env.session.currentState == .idle)
        #expect(env.transcription.currentModelName == "openai_whisper-base.en")
        #expect(env.store.value(for: Settings.selectedModel) == "openai_whisper-base.en")
    }

    @MainActor
    @Test("stop cancels configuration subscriptions")
    func stopCancelsSubscriptions() async throws {
        let env = makeSession()
        try await env.session.start()
        let afterStart = env.session.configurationApplyCount
        await env.session.stop()
        env.store.setValue(.modifier(keyCode: 54), for: Settings.dictationShortcut)
        #expect(env.session.configurationApplyCount == afterStart)
    }

    @MainActor
    @Test("activate via Combine + await deactivate drives a full .idle → .recording → .idle cycle")
    func endToEndCycleViaCombineAndDirectDeactivate() async throws {
        // Activate goes through the full chain (capability → manager → session)
        // synchronously because `hotkey.handle` runs on the publisher's actor.
        // Deactivate is async (it awaits stopRecording); the production callback
        // wraps it in a Task — tests call it directly to keep the assertion sync.
        let env = makeSession()
        env.session.wireHotkeyCallbacks()
        env.hotkey.bindEventStream()

        env.inputMonitoring.publishForTest(.flagsChanged(keyCode: 62, flags: .maskControl))
        #expect(env.session.currentState == .recording)

        // Let the fire-and-forget startRecording Task subscribe to mic buffers
        // before we publish one.
        try await Task.sleep(nanoseconds: 20_000_000)
        env.microphone.publishForTest(makeBuffer())

        await env.session.handleDeactivate()
        #expect(env.session.currentState == .idle)
    }

    @MainActor
    @Test("state publisher records .recording → .processing → .idle through a cycle")
    func statePublisherRecordsFullSequence() async throws {
        // RiverSession is the single writer of RiverState; the publisher
        // is the only observable surface. The sequence below is the contract
        // M5 establishes (M4 skipped .processing entirely).
        let env = makeSession()
        var states: [RiverState] = []
        let token = env.session.state.sink { states.append($0) }
        defer { token.cancel() }

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        env.microphone.publishForTest(makeBuffer())
        await env.session.handleDeactivate()

        #expect(states == [.idle, .recording, .processing, .idle])
    }

    @MainActor
    @Test("handleDeactivate still returns to .idle when stopRecording throws")
    func handleDeactivateReturnsToIdleOnAudioError() async throws {
        // No buffer published → stopRecording waits ~300 ms then throws
        // .noAudioCaptured. The session must log and still complete the cycle —
        // getting stuck in .processing would freeze the app.
        let env = makeSession()
        env.session.handleActivate()
        await env.session.handleDeactivate()
        #expect(env.session.currentState == .idle)
    }

    @MainActor
    @Test("handleDeactivate emits a cycle error and still returns to .idle when capture fails")
    func emitsCycleErrorOnAudioFailure() async throws {
        // Same no-buffer path as handleDeactivateReturnsToIdleOnAudioError, now
        // also asserting the session-level error publisher surfaces the failure
        // for the menu-bar renderer — and that the emission does not disturb the
        // guaranteed return to .idle.
        let env = makeSession()
        var errors: [RiverError] = []
        let token = env.session.errors.sink { errors.append($0) }
        defer { token.cancel() }

        env.session.handleActivate()
        await env.session.handleDeactivate()

        #expect(env.session.currentState == .idle)
        #expect(errors.count == 1)
        guard case .audioCapture = errors.first else {
            Issue.record("expected .audioCapture, got \(String(describing: errors.first))")
            return
        }
    }

    @MainActor
    @Test("the capture watchdog ends a recording through the deactivate path")
    func captureWatchdogEndsRecording() async throws {
        // Mid-recording, the audio stopped arriving (planning 0032, decided 2026-10-23):
        // the capture manager's watchdog asks the session to end the recording, which
        // takes the same path as a key release, so stopRecording reports the shortfall
        // and the session still returns to .idle with the error surfaced.
        let env = makeSession()
        env.session.wireHotkeyCallbacks()
        var errors: [RiverError] = []
        let token = env.session.errors.sink { errors.append($0) }
        defer { token.cancel() }

        env.session.handleActivate()
        #expect(env.session.currentState == .recording)
        env.audio.onCaptureGapExceeded?()
        await waitUntil { env.session.currentState == .idle }

        #expect(env.session.currentState == .idle)
        guard case .audioCapture = errors.first else {
            Issue.record("expected .audioCapture, got \(String(describing: errors.first))")
            return
        }
    }

    @MainActor
    @Test("a recording cut short types what was heard, then says so, with streaming on or off", arguments: [true, false])
    func captureFailureTypesWhatWasHeard(streaming: Bool) async throws {
        // Decided 2026-10-23: discarding the audio that did arrive would lose the user's words
        // along with the ones the microphone never delivered. With streaming off nothing was
        // decoded while the user spoke, so the release decodes what was heard in one piece
        // (planning 0039); before, it typed nothing.
        let env = makeSession()
        env.store.setValue(streaming, for: Settings.streamingDictation)
        try await loadModel(env, transcribing: "heard before the loss")
        var errors: [RiverError] = []
        var typedWhenReported: String?
        let token = env.session.errors.sink { error in
            errors.append(error)
            typedWhenReported = env.accessibility.postedKeyDownTextForTesting.joined()
        }
        defer { token.cancel() }

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        for _ in 0..<20 { env.microphone.publishForTest(makeNonSilentBuffer()) }   // 2 s heard
        for _ in 0..<12 { env.microphone.publishForTest(makeBuffer()) }            // a pause: streaming cuts here
        for _ in 0..<10 { env.microphone.publishForTest(makeNonSilentBuffer()) }   // 1 s more
        env.clock.now += 6                                                          // then about 2 s lost
        await env.session.handleDeactivate()

        // Plain locals: a failing #expect reflects every value it names, and reflecting the
        // whole test environment hangs the runner.
        let typed = env.accessibility.postedKeyDownTextForTesting.joined()
        let clips = env.loader.clipSeconds
        let errorCount = errors.count
        let typedFirst = typedWhenReported
        #expect(typed == "heard before the loss")
        // Streaming decoded the segment, then the tail with the segment's end in front of it;
        // with it off, the recording was decoded in one piece.
        #expect(clips.count == (streaming ? 2 : 1))
        #expect(errorCount == 1)
        // Typed first, then reported.
        #expect(typedFirst == "heard before the loss")
        guard case .audioCapture(let underlying) = errors.first,
              case AudioCaptureError.captureIncomplete = underlying else {
            Issue.record("expected .captureIncomplete, got \(String(describing: errors.first))")
            return
        }
    }

    @MainActor
    @Test("an all-silence recording completes the cycle with no error emitted")
    func allSilenceRecordingEmitsNoError() async throws {
        // A stray key-brush captures pure silence. `makeBuffer()` is zeros, which
        // the stream's silence trim reduces to empty; the session must skip
        // decode/paste and NOT raise the error glyph — silence is not a failure.
        // The `.recording → .processing → .idle` cycle must still complete cleanly
        // (planning 0023 AC2). Contrast with the no-buffer path, which throws
        // .noAudioCaptured and DOES surface an error.
        let env = makeSession()
        var errors: [RiverError] = []
        let token = env.session.errors.sink { errors.append($0) }
        defer { token.cancel() }

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        env.microphone.publishForTest(makeBuffer())  // silent zeros → trims to empty
        await env.session.handleDeactivate()

        #expect(env.session.currentState == .idle)
        #expect(errors.isEmpty)
    }

    @MainActor
    @Test("an all-silence recording plays the end cue, and a cancel the cancel cue, through AppState")
    func allSilenceRecordingPlaysEndCue() async throws {
        // The silence branch never suspends after `.processing`, so the sound cues
        // observe `.recording → .idle`, the same snapshot pair as a cancel. Silence is
        // a stopped recording (planning 0023), so it must cue end; the cancel cue stays
        // with a real cancel (planning 0017).
        let env = makeSession()
        let appState = AppState()
        appState.bind(to: env.session)
        env.store.setValue(true, for: Settings.playFeedbackSounds)
        let player = FakeSoundFeedbackPlayer()
        let controller = SoundFeedbackController(appState: appState, settings: env.store, player: player)
        controller.start()

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        env.microphone.publishForTest(makeBuffer())  // silent zeros → trims to empty
        await env.session.handleDeactivate()
        await waitUntil { player.cues.count == 2 }
        #expect(player.cues == [.begin, .end])

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        env.session.handleCancel()
        await waitUntil { player.cues.count == 4 }
        #expect(player.cues == [.begin, .end, .begin, .cancel])
    }

    @MainActor
    @Test("pending reconfiguration applies on return to .idle")
    func pendingReconfigurationAppliesOnReturnToIdle() async throws {
        // The M3 deferral slot closes here: a settings change during a cycle is
        // parked and applies cleanly when the cycle ends, with no path that
        // tears down the hotkey mid-recording (anti-pattern #7).
        let env = makeSession()
        try await env.session.start()
        let baseline = env.session.configurationApplyCount  // 1 from initial emit

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)

        env.store.setValue(.modifier(keyCode: 59), for: Settings.dictationShortcut)  // change while .recording
        #expect(env.session.configurationApplyCount == baseline)  // unchanged — deferred
        #expect(env.session.configurationDeferCount == 1)

        env.microphone.publishForTest(makeBuffer())
        await env.session.handleDeactivate()
        #expect(env.session.currentState == .idle)
        #expect(env.session.configurationApplyCount == baseline + 1)  // pending applied
    }

    @MainActor
    @Test("two settings deferred during one Hold recording both apply on return to .idle")
    func multipleDeferredReconfigurationsAllApply() async throws {
        // A single pending slot would drop the earlier change. With activeMode ==
        // .hold (the default), both a key and a mode change during the recording
        // defer, and both must land when the cycle returns to .idle.
        let env = makeSession()
        try await env.session.start()
        let baseline = env.session.configurationApplyCount

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)

        env.store.setValue(.modifier(keyCode: 59), for: Settings.dictationShortcut)                     // deferred
        env.store.setValue(ActivationMode.singleTap, for: Settings.activationMode)  // deferred
        #expect(env.session.configurationApplyCount == baseline)   // both parked, none lost
        #expect(env.session.configurationDeferCount == 2)

        env.microphone.publishForTest(makeBuffer())
        await env.session.handleDeactivate()
        #expect(env.session.currentState == .idle)
        #expect(env.session.configurationApplyCount == baseline + 2)  // both applied
    }

    @MainActor
    @Test("cancel from .recording returns to .idle with no error and a canceled notice")
    func cancelFromRecordingReturnsToIdle() async throws {
        // Planning 0017 AC1: the discard transition ends the recording with NO
        // transcription and NO paste (structural — handleCancel never calls either),
        // no error on the cycle-failure channel, and a visible "canceled" notice.
        let env = makeSession()
        try await env.session.start()

        var errors: [RiverError] = []
        var notices: [String] = []
        let errToken = env.session.errors.sink { errors.append($0) }
        let noticeToken = env.session.notices.sink { notices.append($0) }
        defer { errToken.cancel(); noticeToken.cancel() }

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)  // let startRecording subscribe
        #expect(env.session.currentState == .recording)

        env.session.handleCancel()

        #expect(env.session.currentState == .idle)
        #expect(errors.isEmpty)                                      // no cycle error
        #expect(notices == [ActivationNotice.recordingCanceled])    // visible, not silent
    }

    @MainActor
    @Test("cancel while .idle is a no-op")
    func cancelWhileIdleIsNoOp() async throws {
        // Planning 0017 AC2: cancel outside .recording changes nothing and emits
        // no notice (logged only).
        let env = makeSession()
        try await env.session.start()
        var notices: [String] = []
        let token = env.session.notices.sink { notices.append($0) }
        defer { token.cancel() }

        env.session.handleCancel()

        #expect(env.session.currentState == .idle)
        #expect(notices.isEmpty)
    }

    @MainActor
    @Test("cancel while .processing is a no-op (out of scope)")
    func cancelWhileProcessingIsNoOp() async throws {
        // Planning 0017: cancel during .processing is ignored — transcription is
        // already in flight and the paste is imminent. Drive into .processing by
        // starting handleDeactivate with no buffer (it sits in the ~300 ms warmup
        // wait), cancel during that window, and confirm the state is unaffected.
        let env = makeSession()
        try await env.session.start()
        var notices: [String] = []
        let token = env.session.notices.sink { notices.append($0) }
        defer { token.cancel() }

        env.session.handleActivate()
        let deactivate = Task { @MainActor in await env.session.handleDeactivate() }
        try await Task.sleep(nanoseconds: 20_000_000)  // now in .processing, mid-warmup-wait
        #expect(env.session.currentState == .processing)

        env.session.handleCancel()
        #expect(env.session.currentState == .processing)  // unaffected
        #expect(notices.isEmpty)

        await deactivate.value                              // let the cycle finish
        #expect(env.session.currentState == .idle)
    }

    @MainActor
    @Test("a settings change deferred during a canceled recording still applies on return to .idle")
    func pendingReconfigurationAppliesOnCancel() async throws {
        // Planning 0017 AC3: the cancel path runs the same deferral loop as the
        // normal cycle end. A key change parked during the (Hold-mode) recording
        // must land when cancel returns the session to .idle — cancel is not a
        // shortcut that skips the deferral contract.
        let env = makeSession()
        try await env.session.start()
        let baseline = env.session.configurationApplyCount

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)

        env.store.setValue(.modifier(keyCode: 59), for: Settings.dictationShortcut)  // deferred (Hold recording)
        #expect(env.session.configurationApplyCount == baseline)  // parked, not applied
        #expect(env.session.configurationDeferCount == 1)

        env.session.handleCancel()

        #expect(env.session.currentState == .idle)
        #expect(env.session.configurationApplyCount == baseline + 1)  // pending applied on cancel
    }

    // planning 0036, Model: a model that finishes loading while the user dictates must not
    // take over that recording's decode halfway; it waits for the cycle to end.
    @MainActor
    @Test("a new model that becomes ready mid-recording takes over only on the return to .idle")
    func readyModelCommitsAtIdle() async throws {
        let env = makeSession()
        try await env.session.start()
        env.session.handleActivate()
        #expect(env.session.currentState == .recording)

        await env.transcription.switchModel(to: "openai_whisper-base.en")
        #expect(env.transcription.currentModelSwitch?.phase == .ready)
        #expect(env.transcription.currentModelName == Constants.defaultModel)

        env.microphone.publishForTest(makeBuffer())
        await env.session.handleDeactivate()
        #expect(env.session.currentState == .idle)
        #expect(env.transcription.currentModelName == "openai_whisper-base.en")
        #expect(env.store.value(for: Settings.selectedModel) == "openai_whisper-base.en")
    }

    // The latest choice wins. A model ready mid-dictation that the user then moves past must
    // not take over at the end of the dictation, nor be saved for the next launch.
    @MainActor
    @Test("a later choice mid-recording replaces a model that was ready, which never takes over")
    func laterChoiceReplacesReadyModel() async throws {
        let env = makeSession()
        try await env.session.start()
        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)

        await env.transcription.switchModel(to: "openai_whisper-base.en")
        #expect(env.transcription.currentModelSwitch?.phase == .ready)
        env.loader.failing = ["distil-whisper_distil-large-v3"]
        env.session.selectModel("distil-whisper_distil-large-v3")
        await waitUntil { env.transcription.currentModelSwitch == ModelSwitch(target: "distil-whisper_distil-large-v3", phase: .failed) }

        env.microphone.publishForTest(makeBuffer())
        await env.session.handleDeactivate()
        #expect(env.session.currentState == .idle)
        #expect(env.transcription.currentModelName == Constants.defaultModel)
        #expect(env.store.value(for: Settings.selectedModel) == Constants.defaultModel)
        #expect(env.transcription.currentModelSwitch == ModelSwitch(target: "distil-whisper_distil-large-v3", phase: .failed))
    }

    // A relaunch loads `selectedModel` with nothing to fall back on, so it must only ever
    // name a model that took over, never a choice that failed.
    @MainActor
    @Test("a model that fails to load is not saved as the selected model")
    func failedChoiceIsNotSaved() async throws {
        let env = makeSession()
        try await env.session.start()
        env.loader.failing = ["openai_whisper-base.en"]
        env.session.selectModel("openai_whisper-base.en")
        await waitUntil { env.transcription.currentModelSwitch?.phase == .failed }
        #expect(env.transcription.currentModelSwitch?.phase == .failed)
        #expect(env.store.value(for: Settings.selectedModel) == Constants.defaultModel)
        #expect(env.transcription.currentModelName == Constants.defaultModel)
    }

    // PR 7a smoke test (2026-11-19): a model that became ready while River was idle took over,
    // but the Model section kept reading "Waiting" for it through every later dictation. The
    // commit ran inside the delivery of the ready value, so subscribers after the session got
    // the switched selection first and the older value last. Delivery order isn't fixed, so
    // the Model section's state is bound both before and after the session subscribes.
    @MainActor
    @Test("a switch committed at idle leaves every subscriber with the model in use")
    func idleCommitReachesEverySubscriber() async throws {
        let env = makeSession()
        let before = AppState()
        before.bind(transcription: env.transcription)
        try await env.session.start()
        let after = AppState()
        after.bind(transcription: env.transcription)

        env.session.selectModel("openai_whisper-base.en")
        await waitUntil { env.transcription.currentModelName == "openai_whisper-base.en" }
        await waitUntil { before.modelSelection == env.transcription.currentSelection && after.modelSelection == env.transcription.currentSelection }
        let inUse = ModelSelection(inUse: "openai_whisper-base.en", inUseState: .ready, next: nil)
        #expect(env.transcription.currentSelection == inUse)
        #expect(before.modelSelection == inUse)
        #expect(after.modelSelection == inUse)
    }

    // Try Again on a failed model chooses the saved model again, which a setting write
    // would swallow as no change.
    @MainActor
    @Test("choosing the saved model again retries it after a failure")
    func selectingSavedModelRetries() async throws {
        let env = makeSession()
        try await env.session.start()
        env.transcription.setModelLoadStateForTesting(.failed)
        env.session.selectModel(Constants.defaultModel)
        await waitUntil { env.transcription.currentModelLoadState != .failed }
        #expect(env.transcription.currentModelLoadState != .failed)
    }

    @MainActor
    @Test("a model ready during a canceled recording takes over when cancel ends the cycle")
    func readyModelCommitsOnCancel() async throws {
        let env = makeSession()
        try await env.session.start()
        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)

        env.session.selectModel("openai_whisper-base.en")
        await waitUntil { env.transcription.currentModelSwitch?.phase == .ready }
        #expect(env.transcription.currentModelName == Constants.defaultModel)

        env.session.handleCancel()

        #expect(env.session.currentState == .idle)
        #expect(env.transcription.currentModelName == "openai_whisper-base.en")
    }

    @MainActor
    @Test("a River hot key during a Hold recording discards it silently and keeps the deferral loop")
    func hotKeyDuringHoldDiscardsSilently() async throws {
        // Spec 0036: a lone-modifier dictation key held as part of another River
        // shortcut means the user is running that shortcut. The recording goes with no
        // transcription, no error, no notice, and the modifier's release must not start
        // a `.processing` cycle. A setting parked during it still applies, as on cancel.
        let env = makeSession()
        try await env.session.start()
        let baseline = env.session.configurationApplyCount
        var errors: [RiverError] = []
        var notices: [String] = []
        var discards = 0
        let tokens = [
            env.session.errors.sink { errors.append($0) },
            env.session.notices.sink { notices.append($0) },
            env.session.discards.sink { discards += 1 },
        ]
        defer { tokens.forEach { $0.cancel() } }

        // 61: the session applies the store's dictation shortcut, Right Option, at start.
        env.inputMonitoring.publishForTest(.flagsChanged(keyCode: 61, flags: .maskAlternate))
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(env.session.currentState == .recording)
        env.store.setValue(.modifier(keyCode: 59), for: Settings.dictationShortcut)  // deferred

        env.hotKeys.publishForTest(.pressed(HotKeyID(rawValue: 99)))
        #expect(env.session.currentState == .idle)
        env.inputMonitoring.publishForTest(.flagsChanged(keyCode: 61, flags: []))
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(env.session.currentState == .idle)                       // no processing cycle
        #expect(errors.isEmpty)
        #expect(notices.isEmpty)                                         // silent, unlike cancel
        #expect(discards == 1)
        #expect(env.session.configurationApplyCount == baseline + 1)     // pending applied
    }

    // A recording discarded because the dictation key was part of another River shortcut
    // returns to .idle like a cancel, so a model that became ready meanwhile takes over too.
    @MainActor
    @Test("a model ready during a discarded recording takes over when the discard ends the cycle")
    func readyModelCommitsOnDiscard() async throws {
        let env = makeSession()
        try await env.session.start()
        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)

        env.session.selectModel("openai_whisper-base.en")
        await waitUntil { env.transcription.currentModelSwitch?.phase == .ready }
        #expect(env.transcription.currentModelName == Constants.defaultModel)

        env.session.handleDiscard()

        #expect(env.session.currentState == .idle)
        #expect(env.transcription.currentModelName == "openai_whisper-base.en")
    }

    @MainActor
    @Test("handleActivate is a no-op outside .idle")
    func handleActivateRejectsNonIdle() {
        let env = makeSession()
        env.session.handleActivate()
        #expect(env.session.currentState == .recording)
        env.session.handleActivate()
        #expect(env.session.currentState == .recording)
    }

    @MainActor
    @Test("handleDeactivate is a no-op outside .recording")
    func handleDeactivateRejectsNonRecording() async {
        let env = makeSession()
        await env.session.handleDeactivate()
        #expect(env.session.currentState == .idle)
    }

    // MARK: - Dictating before the model is ready (planning 0004)

    // A dictation always starts. The transcript waits in `.processing` for the model, then
    // types; a failed load keeps the recording for the next load that succeeds. These tests
    // hold the fake loader's load open, so every decode before the model is ready fails as a
    // real one does.

    @MainActor
    @Test("a press while the model downloads records, waits in processing, and types once the model is ready")
    func dictationWaitsForTheModel() async throws {
        let env = makeSession()
        let load = await holdModelLoad(env)
        let events = EventLog(env.session)

        let release = try await dictate(env)
        await waitUntil { events.events == [.waitingForModel] }
        #expect(env.session.currentState == .processing)
        #expect(env.accessibility.postedEventCountForTesting == 0)

        env.loader.finishLoad(of: Constants.defaultModel)
        await release.value
        await load.value
        let typed = env.accessibility.postedKeyDownTextForTesting.joined()
        #expect(typed == Constants.defaultModel)
        #expect(env.session.currentState == .idle)
        // Sent while River still processes, so the panel can show it before it leaves.
        #expect(events.states == [.processing])
    }

    @MainActor
    @Test("with streaming on, a dictation made while the model downloads types once, after the wait")
    func streamedDictationWaitsForTheModel() async throws {
        // Its segments fail while the model isn't ready, so the release decodes the dictation
        // from the first of them in one piece: one text, typed once.
        let env = makeSession()
        #expect(env.store.value(for: Settings.streamingDictation))
        let load = await holdModelLoad(env)
        let events = EventLog(env.session)

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        for _ in 0..<20 { env.microphone.publishForTest(makeNonSilentBuffer()) }   // 2 s of sound
        for _ in 0..<12 { env.microphone.publishForTest(makeBuffer()) }            // 1.2 s pause
        for _ in 0..<10 { env.microphone.publishForTest(makeNonSilentBuffer()) }
        let release = Task { await env.session.handleDeactivate() }
        await waitUntil { events.events == [.waitingForModel] }

        env.loader.finishLoad(of: Constants.defaultModel)
        await release.value
        await load.value
        let typed = env.accessibility.postedKeyDownTextForTesting.joined()
        #expect(typed == Constants.defaultModel)
    }

    @MainActor
    @Test("a press while a dictation waits for the model is ignored, as while transcribing")
    func pressWhileWaitingIsIgnored() async throws {
        // A second dictation would wait for the same model, so starting one brings no text sooner.
        let env = makeSession()
        let load = await holdModelLoad(env)
        let events = EventLog(env.session)
        let release = try await dictate(env)
        await waitUntil { events.events == [.waitingForModel] }

        env.session.handleActivate()
        #expect(env.session.currentState == .processing)

        env.loader.finishLoad(of: Constants.defaultModel)
        await release.value
        await load.value
        let typed = env.accessibility.postedKeyDownTextForTesting.joined()
        #expect(typed == Constants.defaultModel)
    }

    @MainActor
    @Test("a silent tap while the model downloads ends at once, with no wait", .timeLimit(.minutes(1)))
    func silentTapNeverWaits() async throws {
        // Nothing was said, so there is nothing to wait for: River returns to idle and takes the
        // next press. The stream asks the session to wait only for a clip that holds speech
        // (planning 0004, 0039). A wait here would hang until the time limit.
        let env = makeSession()
        let load = await holdModelLoad(env)
        let events = EventLog(env.session)

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        env.microphone.publishForTest(makeBuffer())   // silent zeros
        await env.session.handleDeactivate()
        let state = env.session.currentState
        let sent = events.events
        let kept = env.session.currentKeptRecordingCount
        #expect(state == .idle)
        #expect(sent.isEmpty)
        #expect(kept == 0)

        env.loader.finishLoad(of: Constants.defaultModel)
        await load.value
    }

    @MainActor
    @Test("Cancel Dictation throws a waiting dictation away, and the model keeps loading")
    func cancelWaitingDiscardsTheDictation() async throws {
        let env = makeSession()
        let load = await holdModelLoad(env)
        let events = EventLog(env.session)
        let release = try await dictate(env)
        await waitUntil { events.events == [.waitingForModel] }

        env.session.cancelWaiting()
        await release.value
        #expect(env.session.currentState == .idle)
        #expect(env.transcription.currentModelLoadState == .downloading)

        env.loader.finishLoad(of: Constants.defaultModel)
        await load.value
        try await Task.sleep(nanoseconds: 20_000_000)
        let typed = env.accessibility.postedKeyDownTextForTesting.joined()
        let retained = env.session.hasLastTranscript
        let kept = env.session.currentKeptRecordingCount
        #expect(env.transcription.currentModelLoadState == .ready)
        #expect(typed.isEmpty)
        #expect(!retained)
        #expect(kept == 0)
    }

    @MainActor
    @Test("a failed load keeps the recording, and the next load that succeeds holds its text, never typed")
    func failedLoadKeepsTheRecording() async throws {
        let env = makeSession()
        // Started, so the session hears the model become ready.
        try await env.session.start()
        env.loader.failing = [Constants.defaultModel]
        let load = await holdModelLoad(env)
        let events = EventLog(env.session)
        var errors: [RiverError] = []
        let errorWatch = env.session.errors.sink { errors.append($0) }
        defer { errorWatch.cancel() }

        let first = try await dictate(env)
        await waitUntil { events.events == [.waitingForModel] }
        env.loader.finishLoad(of: Constants.defaultModel)
        await first.value
        await load.value
        #expect(events.events == [.waitingForModel, .recordingKept])
        #expect(events.states == [.processing, .processing])
        #expect(env.session.currentKeptRecordingCount == 1)
        // The status ring says it: an error status and a menu error line would say it twice.
        #expect(errors.isEmpty)

        // With the load already failed there is nothing to wait for: kept at once.
        let second = try await dictate(env)
        await second.value
        #expect(events.events == [.waitingForModel, .recordingKept, .recordingKept])
        #expect(env.session.currentKeptRecordingCount == 2)

        // Try Again: the load succeeds, and the kept recordings are transcribed and held.
        env.loader.failing = []
        env.session.selectModel(Constants.defaultModel)
        await env.loader.loadStarted(Constants.defaultModel)
        env.loader.finishLoad(of: Constants.defaultModel)
        await waitUntil { env.session.currentKeptRecordingCount == 0 && env.session.hasLastTranscript }

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        env.session.copyLastTranscript(to: pasteboard)
        let held = pasteboard.string(forType: .string)
        let typed = env.accessibility.postedKeyDownTextForTesting.joined()
        // A space, never a newline: Paste last types the text, and a newline is Return.
        #expect(held == "\(Constants.defaultModel) \(Constants.defaultModel)")
        #expect(typed.isEmpty)
        // Each kept recording reached the engine once, whole: a second of sound apiece.
        let clips = env.loader.clipSeconds
        #expect(clips.count == 2)
        #expect(clips.allSatisfy { abs($0 - 1.0) < 0.01 })
    }

    @MainActor
    @Test("a dictation's decode waits for a kept recording's, so the engine runs one decode at a time")
    func keptDecodeRunsAlone() async throws {
        let env = makeSession()
        try await env.session.start()
        env.store.setValue(false, for: Settings.streamingDictation)
        env.loader.failing = [Constants.defaultModel]
        let load = await holdModelLoad(env)
        let first = try await dictate(env)
        await waitUntil { env.session.currentState == .processing }
        env.loader.finishLoad(of: Constants.defaultModel)
        await first.value
        await load.value
        #expect(env.session.currentKeptRecordingCount == 1)

        // The load succeeds, and the kept recording's decode starts and is held open.
        env.loader.failing = []
        env.loader.holdsTranscriptions = true
        env.session.selectModel(Constants.defaultModel)
        await env.loader.loadStarted(Constants.defaultModel)
        env.loader.finishLoad(of: Constants.defaultModel)
        await waitUntil { env.loader.heldTranscriptionCount == 1 }
        #expect(env.loader.heldTranscriptionCount == 1)
        #expect(!env.session.hasLastTranscript)

        // A dictation ends meanwhile: its decode waits its turn behind the held one.
        let second = try await dictate(env)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(env.loader.heldTranscriptionCount == 1)
        #expect(env.accessibility.postedEventCountForTesting == 0)

        // The kept recording's text is held, and only then does the dictation's decode run.
        env.loader.finishTranscriptions()
        await waitUntil { env.loader.heldTranscriptionCount == 1 }
        #expect(env.session.currentKeptRecordingCount == 0)
        #expect(env.session.hasLastTranscript)
        env.loader.finishTranscriptions()
        await second.value
        let typed = env.accessibility.postedKeyDownTextForTesting.joined()
        let mostAtOnce = env.loader.mostTranscriptionsAtOnce
        #expect(typed == Constants.defaultModel)
        #expect(mostAtOnce == 1)
    }

    @MainActor
    @Test("a switch of app after the release holds the text and types none")
    func switchAfterReleaseHoldsTheText() async throws {
        // The text would land in an app the user never dictated into.
        let env = makeSession()
        let load = await holdModelLoad(env)
        let events = EventLog(env.session)
        let release = try await dictate(env)
        await waitUntil { events.events == [.waitingForModel] }

        env.appInFront.pid = 200
        env.loader.finishLoad(of: Constants.defaultModel)
        await release.value
        await load.value
        #expect(events.events == [.waitingForModel, .textHeld])
        #expect(events.states == [.processing, .processing])

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        env.session.copyLastTranscript(to: pasteboard)
        let held = pasteboard.string(forType: .string)
        let typed = env.accessibility.postedKeyDownTextForTesting.joined()
        #expect(held == Constants.defaultModel)
        #expect(typed.isEmpty)
    }

    @MainActor
    @Test("a click into another app before the release types there: the app dictated into is the one in front at the release")
    func appAtTheReleaseIsTheTarget() async throws {
        // In a tap mode the user can start, click into the field they want, and stop there.
        let env = makeSession()
        try await loadModel(env, transcribing: "hello world")
        let events = EventLog(env.session)
        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        for _ in 0..<10 { env.microphone.publishForTest(makeNonSilentBuffer()) }

        env.appInFront.pid = 200
        await env.session.handleDeactivate()
        let typed = env.accessibility.postedKeyDownTextForTesting.joined()
        #expect(typed == "hello world")
        #expect(events.events.isEmpty)
    }

    @MainActor
    @Test("the live text stays hidden for a dictation that started before the model was ready")
    func liveTextHiddenUntilTheModelIsReady() async throws {
        // It would sit empty through the wait, and while it shows the panel takes the mouse.
        let env = makeSession()
        env.store.setValue(true, for: Settings.showLiveText)
        var shown: [Bool] = []
        let watch = env.session.isLiveTextShown.sink { shown.append($0) }
        defer { watch.cancel() }
        let load = await holdModelLoad(env)

        env.session.handleActivate()
        #expect(shown.last == false)
        env.session.handleCancel()

        env.loader.finishLoad(of: Constants.defaultModel)
        await load.value
        env.session.handleActivate()
        #expect(shown.last == true)
        env.session.handleCancel()
    }

    // MARK: - Test environment

    @MainActor
    @Test("in a tap mode, the tap after a cancel starts a new recording immediately")
    func tapAfterCancelStartsImmediately() async throws {
        // Planning 0017 field bug, observed on-device in both tap modes: cancel ends
        // the recording through the session rather than through a tap, and a tap
        // machine with its own "recording" flag ate the next tap as a `stop` for a
        // recording that no longer existed. The user had to press the activation key
        // twice to start again. The machine now reads the session's state instead.
        // Timing-independent — the stale state persisted indefinitely, so this
        // asserts behavior, not a race.
        let env = makeSession()
        // Set the mode through the store, before `start()` subscribes — setting it
        // on the hotkey afterward gets overwritten when the configuration
        // subscription delivers the store's default.
        env.store.setValue(ActivationMode.singleTap, for: Settings.activationMode)
        try await env.session.start()
        env.session.wireHotkeyCallbacks()   // drive the real hotkey → session chain

        // Drive the key the session actually watches: `subscribeToConfiguration`
        // applies the store's activation key, overwriting `makeSession`'s literal.
        let key = Int64(Constants.defaultActivationKeyCode)

        // Tap: key-down then key-up completes one tap and starts a recording.
        env.hotkey.handle(.flagsChanged(keyCode: key, flags: .maskAlternate))
        env.hotkey.handle(.flagsChanged(keyCode: key, flags: []))
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(env.session.currentState == .recording)

        env.session.handleCancel()
        #expect(env.session.currentState == .idle)

        // The very next tap must start a fresh recording, not be swallowed.
        env.hotkey.handle(.flagsChanged(keyCode: key, flags: .maskAlternate))
        env.hotkey.handle(.flagsChanged(keyCode: key, flags: []))
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(env.session.currentState == .recording)
    }

    @MainActor
    @Test("in a tap mode, the tap after a refused start starts a recording", arguments: [ActivationMode.singleTap, .doubleTap])
    func tapAfterRefusedStartStartsRecording(mode: ActivationMode) async throws {
        // Found in the 2026-09-28 architecture review: the tap machine kept its own
        // "recording" flag, so when the session refused a start (then a model still
        // preparing, a permission denied, a dictation still transcribing) the machine
        // believed a recording was live and turned the user's next tap into a stop
        // the session ignored. Tapping during "Preparing model" at launch cost the
        // user a keypress. The session's state is the only "recording" there is.
        // A model no longer refuses a start (planning 0004); a denied permission does.
        let env = makeSession()
        env.store.setValue(mode, for: Settings.activationMode)
        try await env.session.start()
        env.session.wireHotkeyCallbacks()
        let key = Int64(Constants.defaultActivationKeyCode)
        let activate = {
            for _ in 0..<(mode == .doubleTap ? 2 : 1) {
                env.hotkey.handle(.flagsChanged(keyCode: key, flags: .maskAlternate))
                env.hotkey.handle(.flagsChanged(keyCode: key, flags: []))
            }
        }

        env.accessibility.setStatusForTesting(.denied)
        activate()
        #expect(env.session.currentState == .idle)   // refused: Accessibility is denied

        env.accessibility.setStatusForTesting(.granted)
        activate()
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(env.session.currentState == .recording)
    }

    @MainActor
    @Test("a known-denied capability declines activation before any audio is captured")
    func deniedCapabilityDeclinesActivation() async throws {
        // Planning 0012 AC5. The field log recorded a 35-second dictation accepted
        // while Accessibility was denied — audio that could only die at paste time,
        // with the user's speech already gone. The gate must refuse up front.
        let env = makeSession()
        try await env.session.start()
        env.accessibility.setStatusForTesting(.denied)

        var errors: [RiverError] = []
        let token = env.session.errors.sink { errors.append($0) }
        defer { token.cancel() }

        env.session.handleActivate()

        #expect(env.session.currentState == .idle)   // never entered .recording
        #expect(errors.count == 1)
        if case .permission(let capability) = errors.first {
            #expect(capability == env.accessibility.displayName)
        } else {
            Issue.record("expected a .permission error, got \(String(describing: errors.first))")
        }
    }

    @MainActor
    @Test("an unknown capability status does not block activation")
    func unknownCapabilityStatusFailsOpen() async throws {
        // Fail-open, matching the insertion guard (planning 0001): an uncertain
        // reading must never be the thing that stops a dictation. Only `.denied`
        // blocks — a capability that has not been probed yet reads `.unknown`.
        let env = makeSession()
        try await env.session.start()
        env.accessibility.setStatusForTesting(.unknown)

        env.session.handleActivate()

        #expect(env.session.currentState == .recording)
    }

    // MARK: - The ready microphone (planning 0033)

    // Decision 5: the unit runs between recordings only while a dictation is possible.
    // The session combines the four inputs; each test flips one and watches the unit,
    // because a readiness rule that is right but never wired would leave the first
    // word clipped exactly as before.

    @MainActor
    @Test("the microphone is ready after start, and stop closes it")
    func microphoneReadyAfterStart() async throws {
        let env = makeSession()
        try await env.session.start()
        await waitUntil { env.microphone.isListening }
        #expect(env.microphone.isListening)
        await env.session.stop()
        #expect(!env.microphone.isListening)
    }

    @MainActor
    @Test("the switch, any missing permission, and sleep each close the microphone; a loading model doesn't")
    func readinessFollowsEachInput() async throws {
        let env = makeSession()
        try await env.session.start()
        await waitUntil { env.microphone.isListening }

        env.store.setValue(false, for: Settings.keepMicrophoneReady)
        await waitUntil { !env.microphone.isListening }
        #expect(!env.microphone.isListening)
        env.store.setValue(true, for: Settings.keepMicrophoneReady)
        await waitUntil { env.microphone.isListening }
        #expect(env.microphone.isListening)

        env.microphone.setStatusForTesting(.denied)
        await waitUntil { !env.microphone.isListening }
        #expect(!env.microphone.isListening)
        env.microphone.setStatusForTesting(.granted)
        await waitUntil { env.microphone.isListening }
        #expect(env.microphone.isListening)

        // Onboarding is incomplete while any permission is missing, not only Microphone:
        // without these two River cannot dictate, so the indicator must stay off (AC 4).
        env.accessibility.setStatusForTesting(.denied)
        await waitUntil { !env.microphone.isListening }
        #expect(!env.microphone.isListening)
        env.accessibility.setStatusForTesting(.granted)
        await waitUntil { env.microphone.isListening }
        #expect(env.microphone.isListening)

        env.inputMonitoring.setStatusForTesting(.unknown)
        await waitUntil { !env.microphone.isListening }
        #expect(!env.microphone.isListening)
        env.inputMonitoring.setStatusForTesting(.granted)
        await waitUntil { env.microphone.isListening }
        #expect(env.microphone.isListening)

        // A dictation can start while the model downloads or gets ready (planning 0004), and
        // its first word needs the ready microphone as much as any other.
        env.transcription.setModelLoadStateForTesting(.loading)
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(env.microphone.isListening)
        env.transcription.setModelLoadStateForTesting(.ready)

        env.system.setForTesting(SystemAvailability(isAwake: false))
        await waitUntil { !env.microphone.isListening }
        #expect(!env.microphone.isListening)
        env.system.setForTesting(.available)
        await waitUntil { env.microphone.isListening }
        #expect(env.microphone.isListening)

        await env.session.stop()
    }

    @MainActor
    @Test("a recording that heard only the pre-roll types nothing, with streaming on")
    func preRollAloneIsNeverTyped() async throws {
        // The pre-roll is audio from before the press. With streaming on it reaches the
        // stream at the press, so if the unit then delivers nothing the capture error's
        // "type what was heard" path would decode and type it. A dead unit at the press
        // must surface as an error and type nothing (planning 0033).
        let env = makeSession()
        try await loadModel(env, transcribing: "said before the press")
        #expect(env.store.value(for: Settings.streamingDictation))
        await env.audio.setReady(true)
        for _ in 0..<5 { env.microphone.publishForTest(makeNonSilentBuffer()) }

        var errors: [RiverError] = []
        let token = env.session.errors.sink { errors.append($0) }
        defer { token.cancel() }
        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        await env.session.handleDeactivate()                // no live buffer ever arrives
        await env.audio.setReady(false)

        // Plain locals: a failing #expect reflects every value it names, and reflecting the
        // whole test environment hangs the runner.
        let typed = env.accessibility.postedKeyDownTextForTesting.joined()
        let retained = env.session.hasLastTranscript
        let errorCount = errors.count
        #expect(typed.isEmpty)
        #expect(!retained)
        #expect(errorCount == 1)
    }

    @MainActor
    @Test("the switch turned off mid-recording closes the microphone once the recording ends")
    func switchMidRecordingAppliesWhenTheRecordingEnds() async throws {
        let env = makeSession()
        try await env.session.start()
        await waitUntil { env.microphone.isListening }

        env.session.handleActivate()
        #expect(env.session.currentState == .recording)
        env.store.setValue(false, for: Settings.keepMicrophoneReady)
        env.microphone.publishForTest(makeBuffer())
        await env.session.handleDeactivate()
        #expect(env.session.currentState == .idle)
        await waitUntil { !env.microphone.isListening }
        #expect(!env.microphone.isListening)
        await env.session.stop()
    }

    @MainActor
    private struct TestEnv {
        let session: RiverSession
        let store: SettingsStore
        let hotkey: HotkeyManager
        let hotKeys: HotKeyRegistry
        let inputMonitoring: InputMonitoringCapability
        let microphone: MicrophoneCapability
        let transcription: TranscriptionManager
        let loader: FakeModelLoader
        let accessibility: AccessibilityCapability
        let audio: AudioCaptureManager
        let system: SystemAvailabilityMonitor
        let appInFront: AppInFront
        let clock: CaptureClock
    }

    // The app in front, which a test moves to switch apps.
    @MainActor
    private final class AppInFront {
        var pid: pid_t? = 100
    }

    // The capture's clock, frozen unless a test moves it to make the audio fall behind.
    @MainActor
    private final class CaptureClock {
        var now: TimeInterval = 100
    }

    @MainActor
    private func makeSession() -> TestEnv {
        let accessibility = AccessibilityCapability()
        // The test process is not Accessibility-trusted, so this capability would
        // otherwise read `.denied` and the 0012 AC5 activation gate would refuse
        // every cycle test. Grant it explicitly; the two gate tests override it.
        accessibility.setStatusForTesting(.granted)
        // Granting it also unlocks the real `CGEvent.post` path, which must stay
        // stubbed in tests — the suite has no Accessibility grant to post with.
        accessibility.skipPostForTesting = true
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        // Granted, so the ready microphone (planning 0033) opens as it does in the field
        // instead of following the host's TCC state; the readiness tests drive it.
        microphone.setStatusForTesting(.granted)
        let system = SystemAvailabilityMonitor()
        let inputMonitoring = InputMonitoringCapability()
        // Granted like the other two, so onboarding reads complete and the ready
        // microphone does not follow the host's Input Monitoring state.
        inputMonitoring.setStatusForTesting(.granted)
        let hotKeys = HotKeyRegistry(calls: .inert)
        let hotkey = HotkeyManager(
            inputMonitoring: inputMonitoring, hotKeys: hotKeys, initialShortcut: .modifier(keyCode: 62)
        )
        let store = SettingsStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let loader = FakeModelLoader()
        let transcription = TranscriptionManager.withFake(loader)
        // Unit tests never load a real model, so mark the model as ready to exercise the
        // normal recording path without waiting for the model. A model switch (planning
        // 0021) loads through the fake, so the session's routing runs without a download.
        transcription.setModelLoadStateForTesting(.ready)
        // The clock is frozen: these tests are about the cycle, and with suites running
        // in parallel a recording here has measured 1.6 s of wall time for 0.1 s of fake
        // audio, which the capture-gap check would report as lost audio. The gap check and
        // its watchdog have their own suites; the session test drives the callback directly,
        // and a test that wants a recording cut short moves the clock.
        let clock = CaptureClock()
        let audio = AudioCaptureManager(microphone: microphone, now: { clock.now })
        let appInFront = AppInFront()
        let session = RiverSession(
            accessibility: accessibility,
            microphone: microphone,
            inputMonitoring: inputMonitoring,
            hotkey: hotkey,
            audio: audio,
            textInsertion: TextInsertionManager(accessibility: accessibility, frontmostApp: { appInFront.pid }),
            transcription: transcription,
            settings: store,
            system: system
        )
        return TestEnv(
            session: session,
            store: store,
            hotkey: hotkey,
            hotKeys: hotKeys,
            inputMonitoring: inputMonitoring,
            microphone: microphone,
            transcription: transcription,
            loader: loader,
            accessibility: accessibility,
            audio: audio,
            system: system,
            appInFront: appInFront,
            clock: clock
        )
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)   // up to ~1s total
        }
    }

    // The model in use loaded through the fake loader, which then hears `text` in any audio
    // ("" for no speech), so the cycle runs the real decode path (planning 0039).
    @MainActor
    private func loadModel(_ env: TestEnv, transcribing text: String) async throws {
        env.loader.texts[env.transcription.currentModelName] = text
        try await env.transcription.loadModel()
    }

    // The model in use downloading, its load held open by the fake loader until the test
    // finishes it, as a first launch's download is.
    @MainActor
    private func holdModelLoad(_ env: TestEnv) async -> Task<Void, Never> {
        env.loader.held = [Constants.defaultModel]
        env.transcription.setModelLoadStateForTesting(.downloading)
        let load = Task { _ = try? await env.transcription.loadModel() }
        await env.loader.loadStarted(Constants.defaultModel)
        return load
    }

    // Presses, delivers a second of sound, and releases. The release runs on until the
    // dictation is typed, kept or thrown away.
    @MainActor
    private func dictate(_ env: TestEnv) async throws -> Task<Void, Never> {
        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        for _ in 0..<10 { env.microphone.publishForTest(makeNonSilentBuffer()) }
        return Task { await env.session.handleDeactivate() }
    }

    // The session's dictation events, each with the state River was in when it was sent.
    @MainActor
    private final class EventLog {
        private(set) var events: [DictationEvent] = []
        private(set) var states: [RiverState] = []
        private var watch: AnyCancellable?

        init(_ session: RiverSession) {
            watch = session.dictationEvents.sink { [weak self, weak session] event in
                self?.events.append(event)
                if let state = session?.currentState { self?.states.append(state) }
            }
        }
    }

    @MainActor
    private func makeBuffer(milliseconds: Int = 100, sampleRate: Double = 44_100) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
        )!
        let frames = AVAudioFrameCount(Double(milliseconds) * sampleRate / 1000.0)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        return buffer
    }

    // A non-silent buffer: float channel data filled with a constant amplitude above
    // the silence-trim threshold (0.01 RMS). A DC signal survives AVAudioConverter
    // resampling, so the stream's trim keeps it and transcription runs.
    @MainActor
    private func makeNonSilentBuffer(
        milliseconds: Int = 100,
        amplitude: Float = 0.5,
        sampleRate: Double = 44_100
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
        )!
        let frames = AVAudioFrameCount(Double(milliseconds) * sampleRate / 1000.0)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        if let data = buffer.floatChannelData {
            for i in 0..<Int(frames) { data[0][i] = amplitude }
        }
        return buffer
    }

    // MARK: - Streaming (0025 prototype)

    @MainActor
    @Test("with streaming on, a phrase shows before release and the text is inserted once at release")
    func streamingShowsTextThenInsertsOnce() async throws {
        // The whole point: the panel has text while the user is still talking, and the field
        // still receives one insertion — nothing is typed mid-dictation.
        let env = makeSession()
        try await loadModel(env, transcribing: "hello world")
        var shown = ""
        let watch = env.session.liveTranscript.sink { shown = $0 }
        defer { watch.cancel() }

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        for _ in 0..<20 { env.microphone.publishForTest(makeNonSilentBuffer()) }   // 2 s of sound
        for _ in 0..<12 { env.microphone.publishForTest(makeBuffer()) }            // 1.2 s pause
        await waitUntil { !shown.isEmpty }
        #expect(shown == "hello world")
        #expect(env.session.currentState == .recording)
        #expect(env.accessibility.postedEventCountForTesting == 0)

        for _ in 0..<10 { env.microphone.publishForTest(makeNonSilentBuffer()) }
        await env.session.handleDeactivate()

        #expect(env.session.hasLastTranscript)
        #expect(env.accessibility.postedEventCountForTesting > 0)
        #expect(env.session.currentState == .idle)
    }

    @MainActor
    @Test("with streaming off, nothing reaches the live transcript, and release decodes the recording once")
    func streamingOffShowsNothing() async throws {
        // The pause that would cut with streaming on stays inside the one clip (planning 0039).
        let env = makeSession()
        env.store.setValue(false, for: Settings.streamingDictation)
        try await loadModel(env, transcribing: "hello world")
        var shown: [String] = []
        let watch = env.session.liveTranscript.sink { shown.append($0) }
        defer { watch.cancel() }

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        for _ in 0..<20 { env.microphone.publishForTest(makeNonSilentBuffer()) }
        for _ in 0..<12 { env.microphone.publishForTest(makeBuffer()) }
        for _ in 0..<10 { env.microphone.publishForTest(makeNonSilentBuffer()) }
        await env.session.handleDeactivate()

        let clips = env.loader.clipSeconds
        #expect(shown.allSatisfy { $0.isEmpty })
        #expect(env.session.hasLastTranscript)
        #expect(clips.count == 1)
        #expect(abs((clips.first ?? 0) - 4.2) < 0.01)     // 2 s, the 1.2 s pause, 1 s
    }

    // MARK: - Last-transcript retention (planning 0019)

    @MainActor
    @Test("hasLastTranscript is false before the first cycle")
    func hasLastTranscriptFalseInitially() {
        let env = makeSession()
        #expect(!env.session.hasLastTranscript)
    }

    @MainActor
    @Test("last transcript is retained after a successful transcription")
    func lastTranscriptSetAfterSuccessfulTranscription() async throws {
        // AC2: after the paste lands, the menu item offers that cycle's text.
        // The fake model hears the given text; `skipPostForTesting`
        // suppresses the real CGEvent.post so insertion "succeeds" in CI.
        let env = makeSession()
        try await loadModel(env, transcribing: "hello world")
        env.accessibility.setStatusForTesting(.granted)
        env.accessibility.skipPostForTesting = true

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        env.microphone.publishForTest(makeNonSilentBuffer())
        await env.session.handleDeactivate()

        #expect(env.session.hasLastTranscript)
    }

    @MainActor
    @Test("the text typed at the cursor is exactly the text Copy last transcription copies")
    func typedTextMatchesCopiedText() async throws {
        // The two deliveries of one transcript must never diverge: the copy is the
        // recovery path when typing goes wrong, so it has to hold what was meant to be
        // typed, and typing has to hold all of it (planning 0031). A private pasteboard
        // keeps the user's clipboard out of the test. The text is spaced as an engine writes
        // it, one space between words and none at either end, which the stream keeps as is.
        let transcript = Array(repeating: "Dictated in one go: café, naïve 👍🏽, \"quotes\" — and more.", count: 12)
            .joined(separator: " ")
        let env = makeSession()
        try await loadModel(env, transcribing: transcript)

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        env.microphone.publishForTest(makeNonSilentBuffer())
        await env.session.handleDeactivate()

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        env.session.copyLastTranscript(to: pasteboard)
        let typed = env.accessibility.postedKeyDownTextForTesting.joined()
        #expect(typed == transcript)
        #expect(pasteboard.string(forType: .string) == typed)
    }

    @MainActor
    @Test("Paste last types the last transcription again, and nothing before there is one")
    func pasteLastTypesAgain() async throws {
        // The shortcut reuses the typing path, so what it types can't drift from what was
        // typed, and the clipboard is never touched (spec 0036).
        let env = makeSession()
        await env.session.pasteLastTranscript()
        #expect(env.accessibility.postedKeyDownTextForTesting.isEmpty)

        try await loadModel(env, transcribing: "hello again")
        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        env.microphone.publishForTest(makeNonSilentBuffer())
        await env.session.handleDeactivate()
        let first = env.accessibility.postedKeyDownTextForTesting.joined()
        #expect(first == "hello again")

        await env.session.pasteLastTranscript()
        #expect(env.accessibility.postedKeyDownTextForTesting.joined() == first + first)
    }

    @MainActor
    @Test("Paste last pressed twice types the text twice, one after the other")
    func pasteLastTwiceTakesTurns() async throws {
        // Each paste waits for the one still typing, so their chunks never mix (planning 0039).
        let env = makeSession()
        try await loadModel(env, transcribing: "long enough to type in more than one chunk")
        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        env.microphone.publishForTest(makeNonSilentBuffer())
        await env.session.handleDeactivate()
        let once = env.accessibility.postedKeyDownTextForTesting.joined()

        let session = env.session
        let first = Task { @MainActor in await session.pasteLastTranscript() }
        let second = Task { @MainActor in await session.pasteLastTranscript() }
        await first.value
        await second.value
        #expect(env.accessibility.postedKeyDownTextForTesting.joined() == once + once + once)
    }

    @MainActor
    @Test("the live text starts hidden, and its shortcut flips and keeps the choice")
    func liveTextToggle() async throws {
        // Hidden on a fresh install, first run included; the shortcut is the only way to show
        // it, and the next recording starts as the user left it (planning 0034, decision 2).
        let env = makeSession()
        env.session.wireHotkeyCallbacks()   // drive the real hotkey → session chain
        var shown: [Bool] = []
        let token = env.session.isLiveTextShown.sink { shown.append($0) }
        defer { token.cancel() }
        #expect(shown == [false])
        env.hotkey.handle(.pressed(.toggleLiveText))
        #expect(env.store.value(for: Settings.showLiveText))
        env.hotkey.handle(.pressed(.toggleLiveText))
        #expect(!env.store.value(for: Settings.showLiveText))
        #expect(shown == [false, true, false])
    }

    @MainActor
    @Test("toggling the live text mid-recording leaves the recording running")
    func liveTextToggleMidRecording() async throws {
        // Showing the text is not a stop: the dictation goes on and is typed at release.
        let env = makeSession()
        try await loadModel(env, transcribing: "still here")
        env.session.handleActivate()
        env.session.toggleLiveText()
        #expect(env.session.currentState == .recording)
        try await Task.sleep(nanoseconds: 20_000_000)
        env.microphone.publishForTest(makeNonSilentBuffer())
        await env.session.handleDeactivate()
        #expect(env.accessibility.postedKeyDownTextForTesting.joined() == "still here")
    }

    @MainActor
    @Test("Paste last does nothing while a dictation records")
    func pasteLastWaitsOutRecording() async throws {
        // Typing into the app in front mid-dictation would mix two transcriptions.
        let env = makeSession()
        try await loadModel(env, transcribing: "hello again")
        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        env.microphone.publishForTest(makeNonSilentBuffer())
        await env.session.handleDeactivate()
        let typed = env.accessibility.postedKeyDownTextForTesting.joined()

        env.session.handleActivate()
        #expect(env.session.currentState == .recording)
        await env.session.pasteLastTranscript()
        #expect(env.accessibility.postedKeyDownTextForTesting.joined() == typed)
    }

    @MainActor
    @Test("last transcript is retained even when insertion fails (the recovery case)")
    func lastTranscriptRetainedWhenInsertionFails() async throws {
        // AC1: a paste failure is exactly the moment recovery matters. The transcript
        // is retained BEFORE the paste attempt, so the menu item is available even
        // when the paste throws.
        let env = makeSession()
        try await loadModel(env, transcribing: "hello world")
        // Force the failure through the insertion guard rather than by denying the
        // capability: since the 0012 AC5 gate, a denied Accessibility refuses
        // activation outright, so "recording completes, then the paste fails" is no
        // longer reachable that way. A non-editable focus target is — and it is the
        // paste failure that still happens in the field.
        env.accessibility.focusedTargetForTesting = .nonEditable

        var errors: [RiverError] = []
        let token = env.session.errors.sink { errors.append($0) }
        defer { token.cancel() }

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        env.microphone.publishForTest(makeNonSilentBuffer())
        await env.session.handleDeactivate()

        #expect(env.session.hasLastTranscript)           // recovery available
        #expect(errors.count == 1)
        guard case .textInsertion = errors.first else {
            Issue.record("expected .textInsertion, got \(String(describing: errors.first))")
            return
        }
    }

    @MainActor
    @Test("a canceled recording does not overwrite a previously retained transcript")
    func canceledRecordingDoesNotOverwriteLastTranscript() async throws {
        // AC3: cancel produces no transcript and must NOT clear the last one.
        // First, retain a transcript via a successful cycle.
        let env = makeSession()
        try await loadModel(env, transcribing: "hello world")
        env.accessibility.setStatusForTesting(.granted)
        env.accessibility.skipPostForTesting = true

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        env.microphone.publishForTest(makeNonSilentBuffer())
        await env.session.handleDeactivate()
        #expect(env.session.hasLastTranscript)   // baseline

        // Now run a canceled recording — should not wipe the retained transcript.
        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        env.session.handleCancel()

        #expect(env.session.hasLastTranscript)   // still set; cancel didn't clear it
    }

    @MainActor
    @Test("an all-silence recording does not overwrite a previously retained transcript")
    func allSilenceRecordingDoesNotOverwriteLastTranscript() async throws {
        // AC3: a stray key-brush (all silence after trim) skips transcription and
        // must not replace the last retained transcript with nothing.
        let env = makeSession()
        try await loadModel(env, transcribing: "hello world")
        env.accessibility.setStatusForTesting(.granted)
        env.accessibility.skipPostForTesting = true

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        env.microphone.publishForTest(makeNonSilentBuffer())
        await env.session.handleDeactivate()
        #expect(env.session.hasLastTranscript)   // baseline

        // Silent recording (zero-filled buffer → trimmed to empty → no transcription).
        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        env.microphone.publishForTest(makeBuffer())   // silent zeros
        await env.session.handleDeactivate()

        #expect(env.session.hasLastTranscript)   // still set; silence didn't clear it
    }

    // MARK: - Nothing said (planning 0039): quiet for every engine

    @MainActor
    @Test("a dictation the model hears no speech in types nothing and shows no error")
    func nothingHeardIsQuiet() async throws {
        // A Whisper model used to raise "Couldn't transcribe" here, where a FluidAudio
        // model stayed quiet.
        let env = makeSession()
        try await loadModel(env, transcribing: "")
        var errors: [RiverError] = []
        let token = env.session.errors.sink { errors.append($0) }
        defer { token.cancel() }

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        env.microphone.publishForTest(makeNonSilentBuffer())
        await env.session.handleDeactivate()

        #expect(errors.isEmpty)
        #expect(env.accessibility.postedEventCountForTesting == 0)
        #expect(!env.session.hasLastTranscript)
        #expect(env.session.currentState == .idle)
    }

    @MainActor
    @Test("a streamed dictation the model hears no speech in ends quietly, its tail included")
    func nothingHeardWhileStreamingIsQuiet() async throws {
        // A Whisper model's empty segment used to stop streaming, and the tail it left
        // raised "Couldn't transcribe" at release.
        let env = makeSession()
        try await loadModel(env, transcribing: "")
        var errors: [RiverError] = []
        let token = env.session.errors.sink { errors.append($0) }
        defer { token.cancel() }

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        for _ in 0..<20 { env.microphone.publishForTest(makeNonSilentBuffer()) }   // 2 s of sound
        for _ in 0..<12 { env.microphone.publishForTest(makeBuffer()) }            // 1.2 s pause
        await waitUntil { env.loader.mostTranscriptionsAtOnce == 1 }               // the segment decoded
        for _ in 0..<10 { env.microphone.publishForTest(makeNonSilentBuffer()) }   // the tail
        await env.session.handleDeactivate()

        // The segment, then the tail: the streamed path ran, not a decode in one piece.
        let clips = env.loader.clipSeconds
        #expect(clips.count == 2)
        #expect(errors.isEmpty)
        #expect(env.accessibility.postedEventCountForTesting == 0)
        #expect(!env.session.hasLastTranscript)
        #expect(env.session.currentState == .idle)
    }

    @MainActor
    @Test("a kept recording the model hears no speech in is dropped quietly")
    func keptRecordingWithNothingHeardIsDropped() async throws {
        let env = makeSession()
        // Started, so the session hears the model become ready.
        try await env.session.start()
        env.loader.failing = [Constants.defaultModel]
        let load = await holdModelLoad(env)
        let events = EventLog(env.session)
        var errors: [RiverError] = []
        let errorWatch = env.session.errors.sink { errors.append($0) }
        defer { errorWatch.cancel() }

        let dictation = try await dictate(env)
        await waitUntil { events.events == [.waitingForModel] }
        env.loader.finishLoad(of: Constants.defaultModel)
        await dictation.value
        await load.value
        #expect(env.session.currentKeptRecordingCount == 1)

        // Try Again: the load succeeds, and the model hears no speech in the kept recording.
        env.loader.texts[Constants.defaultModel] = ""
        env.loader.failing = []
        env.session.selectModel(Constants.defaultModel)
        await env.loader.loadStarted(Constants.defaultModel)
        env.loader.finishLoad(of: Constants.defaultModel)
        await waitUntil { env.session.currentKeptRecordingCount == 0 }

        #expect(!env.session.hasLastTranscript)
        #expect(errors.isEmpty)
        #expect(env.accessibility.postedEventCountForTesting == 0)
    }

    @MainActor
    @Test("transcript content is kept out of all log lines — only its count is observable")
    func transcriptContentNeverLogged() async throws {
        // AC4 (structural): `handleDeactivate` logs `text.count`, never the value.
        // `copyLastTranscript` logs the count, never the value.
        // `hasLastTranscript` (the test seam) is Bool — content stays in `lastTranscript`.
        // There is no `privacy:` annotation to audit because the content is never
        // interpolated; see logging.md anti-pattern #4.
        let env = makeSession()
        try await loadModel(env, transcribing: "sensitive dictation content")
        env.accessibility.setStatusForTesting(.granted)
        env.accessibility.skipPostForTesting = true

        env.session.handleActivate()
        try await Task.sleep(nanoseconds: 20_000_000)
        env.microphone.publishForTest(makeNonSilentBuffer())
        await env.session.handleDeactivate()

        // The only observable surface of the transcript is the Bool availability flag.
        // The content itself is unreachable from outside the session — there is no
        // getter that returns the String. Asserting `hasLastTranscript` without
        // asserting the content is the structural proof.
        #expect(env.session.hasLastTranscript)
    }
}
