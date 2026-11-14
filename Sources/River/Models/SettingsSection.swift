import Foundation

/// The Settings window's sections, in rail order (planning 0036, Every setting), with each
/// one's SF Symbol (icon Set B, maintainer, 2026-11-10). Pure, so which section the window
/// opens on is tested without a window.
enum SettingsSection: String, CaseIterable, Identifiable {
    case shortcuts, dictation, model, general, permissions

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shortcuts: "Shortcuts"
        case .dictation: "Dictation"
        case .model: "Model"
        case .general: "General"
        case .permissions: "Permissions"
        }
    }

    var symbolName: String {
        switch self {
        case .shortcuts: "command"
        case .dictation: "mic"
        case .model: "square.stack.3d.up"
        case .general: "switch.2"
        case .permissions: "hand.raised"
        }
    }

    /// The section the window opens on: Permissions while any permission is missing, since
    /// River can't dictate until it's granted; then Shortcuts while the dictation shortcut
    /// fails to register, since it does nothing; otherwise the section shown last, as macOS
    /// settings windows reopen on their last pane.
    static func opening(lastShown: SettingsSection, permissionMissing: Bool, shortcutFailing: Bool) -> SettingsSection {
        if permissionMissing { return .permissions }
        return shortcutFailing ? .shortcuts : lastShown
    }
}
