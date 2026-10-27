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
        microphone: CapabilityStatus,
        model: ModelLoadState,
        system: SystemAvailability
    ) -> Bool {
        // `.unknown` closes the mic: the grant has not been asked for yet, and opening
        // the unit would raise the system prompt from idle rather than from a press.
        !micOnlyWhileDictating
            && microphone == .granted
            && model == .ready
            && system == .available
    }
}
