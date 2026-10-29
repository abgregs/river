import Foundation

/// Whether the Mac can take a dictation right now: awake, unlocked, and in the active
/// user session. `SystemAvailabilityMonitor` tracks it from workspace notifications.
struct SystemAvailability: Equatable {
    var isAwake = true
    var isUnlocked = true
    var isSessionActive = true

    static let available = SystemAvailability()
}

/// Decides whether the capture unit should run between recordings (planning 0033,
/// decision 5). Pure, so the rule is tested without a unit or a session.
enum MicrophoneReadiness {
    static func shouldListen(
        micOnlyWhileDictating: Bool,
        onboardingComplete: Bool,
        model: ModelLoadState,
        system: SystemAvailability
    ) -> Bool {
        // Onboarding complete means every permission is `.granted`, by `OnboardingGate`'s
        // rule: the mic stays closed while the permissions window would show, so the
        // indicator never lights before River can dictate. Microphone is one of those
        // permissions, so a mic still `.unknown` stays closed too, and the system prompt
        // comes from a press, not from idle.
        !micOnlyWhileDictating
            && onboardingComplete
            && model == .ready
            && system == .available
    }
}
