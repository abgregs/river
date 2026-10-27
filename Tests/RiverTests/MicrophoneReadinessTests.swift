import Testing
@testable import River

@Suite("MicrophoneReadiness")
struct MicrophoneReadinessTests {
    // Decision 5 of planning 0033: the microphone is ready only while a dictation is
    // possible. Each test names one condition that must close it on its own, so a
    // regression that drops one check fails the test for that check, not a blur.

    @Test("every input favourable keeps the microphone ready")
    func allFavourableIsReady() {
        #expect(MicrophoneReadiness.shouldListen(
            micOnlyWhileDictating: false, microphone: .granted, model: .ready, system: .available
        ))
    }

    @Test("the switch closes the microphone between dictations")
    func switchCloses() {
        #expect(!MicrophoneReadiness.shouldListen(
            micOnlyWhileDictating: true, microphone: .granted, model: .ready, system: .available
        ))
    }

    @Test("a microphone that is not granted stays closed", arguments: [CapabilityStatus.denied, .unknown])
    func ungrantedCloses(status: CapabilityStatus) {
        // `.unknown` closes it too: the grant has not been asked for, and the system
        // prompt belongs to a press, not to idle.
        #expect(!MicrophoneReadiness.shouldListen(
            micOnlyWhileDictating: false, microphone: status, model: .ready, system: .available
        ))
    }

    @Test("a model that is not ready keeps the microphone closed", arguments: [ModelLoadState.downloading, .loading, .failed])
    func modelNotReadyCloses(model: ModelLoadState) {
        // The first-run download and onboarding happen here: no indicator before the
        // user can dictate.
        #expect(!MicrophoneReadiness.shouldListen(
            micOnlyWhileDictating: false, microphone: .granted, model: model, system: .available
        ))
    }

    @Test("sleep, the lock screen, and an inactive session each close the microphone", arguments: [
        SystemAvailability(isAwake: false),
        SystemAvailability(isUnlocked: false),
        SystemAvailability(isSessionActive: false),
    ])
    func unavailableSystemCloses(system: SystemAvailability) {
        #expect(!MicrophoneReadiness.shouldListen(
            micOnlyWhileDictating: false, microphone: .granted, model: .ready, system: system
        ))
    }
}

@Suite("SystemAvailabilityMonitor")
struct SystemAvailabilityMonitorTests {
    @MainActor
    @Test("starts available and publishes only real changes")
    func startsAvailableAndDedupes() {
        let monitor = SystemAvailabilityMonitor()
        var received: [SystemAvailability] = []
        let token = monitor.availability.sink { received.append($0) }
        defer { token.cancel() }

        #expect(monitor.current == .available)
        monitor.setForTesting(.available)                       // no change, no emission
        monitor.setForTesting(SystemAvailability(isAwake: false))
        #expect(received == [.available, SystemAvailability(isAwake: false)])
    }
}
