import Foundation
import Testing
@testable import River

@MainActor
@Suite("SoundFeedbackController")
struct SoundFeedbackControllerTests {

    // MARK: - Pure cue mapping

    @Test("idle→recording produces begin cue")
    func idleToRecordingIsBegin() {
        #expect(SoundFeedbackController.cue(from: .idle, to: .recording, recordingWasCanceled: false) == .begin)
    }

    @Test("recording→processing produces end cue")
    func recordingToProcessingIsEnd() {
        #expect(SoundFeedbackController.cue(from: .recording, to: .processing, recordingWasCanceled: false) == .end)
    }

    @Test("processing→idle produces no cue")
    func processingToIdleIsNil() {
        #expect(SoundFeedbackController.cue(from: .processing, to: .idle, recordingWasCanceled: false) == nil)
    }

    @Test("idle→processing produces no cue")
    func idleToProcessingIsNil() {
        #expect(SoundFeedbackController.cue(from: .idle, to: .processing, recordingWasCanceled: false) == nil)
    }

    @Test("recording→idle (a canceled recording) produces the cancel cue")
    func recordingToIdleIsCancel() {
        // Planning 0017: cancel transitions .recording → .idle directly, and gets
        // its own cue — not the end cue (which means "now transcribing," and a
        // discard is not that), and not silence (0016 exists for the moment the
        // user is looking at the text field rather than the HUD).
        #expect(SoundFeedbackController.cue(from: .recording, to: .idle, recordingWasCanceled: true) == .cancel)
    }

    @Test("recording→idle after a stop (an all-silence recording) produces the end cue")
    func recordingToIdleAfterStopIsEnd() {
        // The same snapshot pair as a cancel; only the session's record of how the
        // recording ended tells them apart (planning 0023: silence is a quiet stop).
        #expect(SoundFeedbackController.cue(from: .recording, to: .idle, recordingWasCanceled: false) == .end)
    }

    @Test("recording→idle after a silent discard produces no cue")
    func recordingToIdleAfterDiscardIsNil() {
        // Spec 0036: the dictation modifier was part of another River shortcut, so the
        // user never meant to dictate. A cancel cue would announce a recording they did
        // not start, on every use of that shortcut.
        #expect(SoundFeedbackController.cue(
            from: .recording, to: .idle, recordingWasCanceled: false, recordingWasDiscarded: true
        ) == nil)
    }

    @Test("the cancel cue is distinct from the begin and end cues")
    func cancelCueIsDistinct() {
        // The point of a third cue is that it is tellable apart. If a future
        // refactor collapses cancel onto begin or end, this fails.
        let cancel = SoundFeedbackController.cue(from: .recording, to: .idle, recordingWasCanceled: true)
        #expect(cancel != SoundFeedbackController.cue(from: .idle, to: .recording, recordingWasCanceled: false))
        #expect(cancel != SoundFeedbackController.cue(from: .recording, to: .processing, recordingWasCanceled: false))
    }

    // MARK: - handleStateChange with setting on

    @Test("begin cue plays when toggle is on and recording starts")
    func beginCuePlaysWhenEnabled() {
        let (controller, fakePlayer, appState) = makeController(soundsEnabled: true)
        controller.start()

        appState.apply(.recording)
        controller.handleStateChange()

        #expect(fakePlayer.cues == [.begin])
    }

    @Test("end cue plays when toggle is on and recording stops")
    func endCuePlaysWhenEnabled() {
        let (controller, fakePlayer, appState) = makeController(soundsEnabled: true)
        controller.start()

        appState.apply(.recording)
        controller.handleStateChange()
        appState.apply(.processing)
        controller.handleStateChange()

        #expect(fakePlayer.cues == [.begin, .end])
    }

    // MARK: - handleStateChange with setting off

    @Test("no cue plays when toggle is off")
    func noCuePlaysWhenDisabled() {
        let (controller, fakePlayer, appState) = makeController(soundsEnabled: false)
        controller.start()

        appState.apply(.recording)
        controller.handleStateChange()
        appState.apply(.processing)
        controller.handleStateChange()

        #expect(fakePlayer.cues.isEmpty)
    }

    // MARK: - Multiple cycles

    @Test("begin and end cues play for each successive cycle when toggle is on")
    func cuePlaysForMultipleCycles() {
        let (controller, fakePlayer, appState) = makeController(soundsEnabled: true)
        controller.start()

        appState.apply(.recording)
        controller.handleStateChange()
        appState.apply(.processing)
        controller.handleStateChange()
        appState.apply(.idle)
        controller.handleStateChange()   // processing→idle: no cue

        appState.apply(.recording)
        controller.handleStateChange()
        appState.apply(.processing)
        controller.handleStateChange()

        #expect(fakePlayer.cues == [.begin, .end, .begin, .end])
    }

    @Test("a canceled cycle cues begin then cancel, and the next cycle is unaffected")
    func canceledCycleThenNormalCycle() {
        // Exercises previousState bookkeeping across the cancel path: the canceled
        // cycle must not leave the controller mis-tracking state such that the
        // following normal cycle loses or duplicates a cue.
        let (controller, fakePlayer, appState) = makeController(soundsEnabled: true)
        controller.start()

        appState.apply(.recording)
        controller.handleStateChange()
        appState.apply(.idle)            // canceled: recording→idle
        controller.handleStateChange()

        appState.apply(.recording)
        controller.handleStateChange()
        appState.apply(.processing)
        controller.handleStateChange()

        #expect(fakePlayer.cues == [.begin, .cancel, .begin, .end])
    }

    @Test("no cancel cue plays when the toggle is off")
    func cancelCueRespectsTheToggle() {
        // The third cue rides the same single setting — no separate switch.
        let (controller, fakePlayer, appState) = makeController(soundsEnabled: false)
        controller.start()

        appState.apply(.recording)
        controller.handleStateChange()
        appState.apply(.idle)
        controller.handleStateChange()

        #expect(fakePlayer.cues.isEmpty)
    }

    // MARK: - All-silence recording

    @Test("an all-silent recording whose .processing passes within one turn plays the end cue, not cancel")
    func silentRecordingPassingProcessingInOneTurnIsEnd() {
        // Planning 0023: an all-silence recording is a quiet no-op — the session
        // skips decode, so `.processing → .idle` can land in the same main-actor
        // turn and the observer sees `.recording → .idle` with no `.processing`
        // between. The user stopped the recording, so 0016's end cue is right; the
        // cancel cue stays reserved for a real cancel (planning 0017).
        let (controller, fakePlayer, appState) = makeController(soundsEnabled: true)
        controller.start()

        appState.apply(.recording)
        controller.handleStateChange()
        appState.apply(.processing)
        appState.apply(.idle)            // same turn: the observer runs once, after both
        controller.handleStateChange()

        #expect(fakePlayer.cues == [.begin, .end])
    }

    @Test("through the live observation loop, a one-turn .processing still plays the end cue")
    func observationLoopSeesSilentRecordingAsEnd() async {
        // The cause, end to end: Observation's `onChange` schedules one Task per
        // change and re-arms only when it runs, so two changes in one turn reach the
        // controller as one. Drives `start()`'s real loop instead of calling
        // `handleStateChange` by hand.
        let (controller, fakePlayer, appState) = makeController(soundsEnabled: true)
        controller.start()

        appState.apply(.recording)
        await waitUntil { fakePlayer.cues == [.begin] }
        appState.apply(.processing)
        appState.apply(.idle)
        await waitUntil { fakePlayer.cues.count == 2 }

        #expect(fakePlayer.cues == [.begin, .end])
    }

    @Test("through the live observation loop, a real cancel still plays the cancel cue")
    func observationLoopSeesCancelAsCancel() async {
        let (controller, fakePlayer, appState) = makeController(soundsEnabled: true)
        controller.start()

        appState.apply(.recording)
        await waitUntil { fakePlayer.cues == [.begin] }
        appState.apply(.idle)            // canceled: recording→idle, no .processing
        await waitUntil { fakePlayer.cues.count == 2 }

        #expect(fakePlayer.cues == [.begin, .cancel])
    }

    // MARK: - Helpers

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)   // up to ~1s total
        }
    }

    private func makeController(
        soundsEnabled: Bool
    ) -> (SoundFeedbackController, FakeSoundFeedbackPlayer, AppState) {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        store.setValue(soundsEnabled, for: Settings.playFeedbackSounds)
        let appState = AppState()
        let fakePlayer = FakeSoundFeedbackPlayer()
        let controller = SoundFeedbackController(appState: appState, settings: store, player: fakePlayer)
        return (controller, fakePlayer, appState)
    }
}

// MARK: - Fake player

@MainActor
final class FakeSoundFeedbackPlayer: SoundFeedbackPlaying {
    private(set) var cues: [SoundCue] = []
    func play(_ cue: SoundCue) { cues.append(cue) }
}
