import Carbon.HIToolbox
import Foundation

/// The Settings recorder's key logic (spec 0036, The recorder). Pure, so it is tested with
/// synthetic key events, as `TapStateMachine` is; `ShortcutRecorderModel` feeds it the
/// window's key events. A modifier pressed and released with nothing else down records that
/// modifier, keeping its side. A key pressed with modifiers held records the combination.
/// Esc stops, Delete clears, and a key with no modifier is refused.
struct ShortcutRecorder {
    enum Event: Equatable {
        /// A non-modifier key went down with these device-independent modifiers held.
        case keyDown(keyCode: Int, modifiers: ShortcutModifiers, isRepeat: Bool)
        /// A modifier key went down or came up.
        case modifierChanged(keyCode: Int, isDown: Bool)
    }

    enum Outcome: Equatable {
        /// Nothing to decide; the held modifiers may have changed.
        case none
        /// A shortcut to check, then save or refuse.
        case candidate(Shortcut)
        /// Esc: stop, keeping the saved shortcut.
        case stop
        /// Delete: clear the shortcut, where the row allows it.
        case clear
        /// A key with no modifier, which can't be a shortcut.
        case bareKey(keyCode: Int)
    }

    /// The modifiers held now, shown while the recorder listens.
    private(set) var held: ShortcutModifiers = []
    // Modifier keys down now, by keycode, so a side is kept and a key held before recording
    // started is ignored when it comes up.
    private var heldKeys: Set<Int> = []
    // Modifier keys pressed since all were up, and whether another key went down meanwhile:
    // only a chord of one modifier and nothing else records that modifier.
    private var chordKeys: Set<Int> = []
    private var isChordSpent = false

    mutating func handle(_ event: Event) -> Outcome {
        switch event {
        case .keyDown(let keyCode, let modifiers, let isRepeat):
            guard !isRepeat else { return .none }
            isChordSpent = true
            guard modifiers.isEmpty else { return .candidate(.combination(keyCode: keyCode, modifiers: modifiers)) }
            switch keyCode {
            case kVK_Escape: return .stop
            case kVK_Delete, kVK_ForwardDelete: return .clear
            default: return .bareKey(keyCode: keyCode)
            }
        case .modifierChanged(let keyCode, let isDown):
            if isDown {
                if heldKeys.isEmpty {
                    chordKeys = []
                    isChordSpent = false
                }
                heldKeys.insert(keyCode)
                chordKeys.insert(keyCode)
                updateHeld()
                return .none
            }
            guard heldKeys.remove(keyCode) != nil else { return .none }
            updateHeld()
            guard heldKeys.isEmpty, chordKeys.count == 1, !isChordSpent else { return .none }
            return .candidate(.modifier(keyCode: keyCode))
        }
    }

    // As a combination counts the keys held: fn adds nothing.
    private mutating func updateHeld() {
        held = heldKeys.reduce(into: []) { $0.formUnion(ModifierKey(rawValue: $1)?.family ?? []) }
    }
}

/// The line under a recorder's row: how to record, why a shortcut was refused, macOS's
/// warning, or a saved shortcut that does nothing (spec 0036, Conflicts).
struct RecorderLine: Equatable {
    enum Kind: Equatable {
        /// Help, at the description's strength, with no symbol.
        case hint
        case refusal
        case warning
        case failure
    }

    let kind: Kind
    let text: String

    static let recordingDictation = RecorderLine(kind: .hint, text: "Press a modifier alone, or modifiers with a key. Esc stops.")
    static let cannotClear = RecorderLine(kind: .refusal, text: "The dictation shortcut can’t be cleared.")
    static let needsModifier = RecorderLine(kind: .refusal, text: "Add a modifier: ⌃, ⌥, ⇧ or ⌘.")
    static let macOSAlsoUses = RecorderLine(kind: .warning, text: "macOS also uses this shortcut. Both will run.")
    static let busy = RecorderLine(kind: .hint, text: "Available when this dictation ends.")

    static func refused(_ reason: String) -> RecorderLine { RecorderLine(kind: .refusal, text: reason) }

    /// Why the recorder refuses `candidate`, or nil when it saves it. A refusal keeps the
    /// recorder listening, so the next key press tries again (spec 0036, Conflicts).
    static func refusal(
        _ availability: ShortcutAvailability, of candidate: Shortcut,
        osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        character: ShortcutText.KeyCharacter = ShortcutText.layoutCharacter
    ) -> RecorderLine? {
        switch availability {
        case .available, .alsoUsedByMacOS: nil
        case .usedByRiver(let owner):
            .refused("\(owner.label) uses \(ShortcutText.display(candidate, character: character)). Choose another.")
        case .takenByAnotherApp: .refused("Another app uses this shortcut. Choose another.")
        case .refusedByMacOS: .refused(macOSRefusal(of: candidate, osVersion: osVersion))
        }
    }

    // macOS 15.0 and 15.1 refuse a combination whose only modifiers are ⌥ or ⌥⇧ (spec 0036,
    // Accepted limits); the line names the Mac's own version.
    static func macOSRefusal(of candidate: Shortcut, osVersion: OperatingSystemVersion) -> String {
        if case .combination(_, let modifiers) = candidate, modifiers.contains(.option),
           modifiers.isSubset(of: [.option, .shift]), osVersion.majorVersion == 15, osVersion.minorVersion < 2 {
            return "macOS 15.\(osVersion.minorVersion) needs ⌃ or ⌘ in this shortcut. Choose another."
        }
        return "macOS refused this shortcut. Choose another."
    }

    /// A saved shortcut whose registration failed at launch.
    static func notWorking(_ registration: HotKeyRegistration) -> RecorderLine? {
        switch registration {
        case .takenByAnotherApp: RecorderLine(kind: .failure, text: "Not working: another app uses this shortcut.")
        case .refused: RecorderLine(kind: .failure, text: "Not working: macOS refused this shortcut.")
        case .registered: nil
        }
    }
}
