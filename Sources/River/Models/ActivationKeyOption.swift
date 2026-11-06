import Foundation

/// The modifier keys that can be the dictation key on their own, with their
/// `CGEvent` keycodes. Pure presentation data extracted from `SettingsView` so the
/// table is unit-tested without SwiftUI (mirrors `MenuBarPresentation`). The human labels and keycodes are
/// the source-of-truth table in requirements/activation-key-and-mode.md.
struct ActivationKeyOption: Identifiable, Equatable {
    let keyCode: Int
    let label: String
    var id: Int { keyCode }

    /// The 9 supported modifier keys, in picker order. Caps Lock is not one: River's
    /// tap sees one event per Caps Lock press and none on release.
    static let all: [ActivationKeyOption] = [
        .init(keyCode: 62, label: "Right Control"),
        .init(keyCode: 59, label: "Left Control"),
        .init(keyCode: 61, label: "Right Option"),
        .init(keyCode: 58, label: "Left Option"),
        .init(keyCode: 54, label: "Right Command"),
        .init(keyCode: 55, label: "Left Command"),
        .init(keyCode: 60, label: "Right Shift"),
        .init(keyCode: 56, label: "Left Shift"),
        .init(keyCode: 63, label: "Function (Fn)"),
    ]
}
