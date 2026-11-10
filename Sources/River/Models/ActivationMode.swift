import Foundation

/// How the activation key starts and stops a recording. Persisted via
/// `Settings.activationMode` (raw value) and interpreted by `HotkeyManager` —
/// Hold inline, the two tap modes through `TapStateMachine`. See
/// requirements/activation-key-and-mode.md.
enum ActivationMode: String, CaseIterable, Identifiable {
    case hold
    case singleTap
    case doubleTap

    var id: String { rawValue }

    /// Human-readable name for the Settings "Start by" choice (planning 0036: shorter labels).
    var label: String {
        switch self {
        case .hold: return "Hold"
        case .singleTap: return "Tap"
        case .doubleTap: return "Double-tap"
        }
    }

    /// One-line behavior summary shown under the choice, worded for a shortcut.
    var description: String {
        switch self {
        case .hold: return "Hold the shortcut while speaking; release to finish."
        case .singleTap: return "Tap the shortcut to start; tap it again to finish."
        case .doubleTap: return "Double-tap the shortcut to start; tap it once to finish."
        }
    }
}
