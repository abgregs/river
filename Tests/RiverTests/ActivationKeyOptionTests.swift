import Testing
@testable import River

@Suite("ActivationKeyOption")
struct ActivationKeyOptionTests {
    @Test("table lists the 8 supported keys, no duplicate keycodes, includes the default")
    func tableComplete() {
        #expect(ActivationKeyOption.all.count == 8)
        let codes = Set(ActivationKeyOption.all.map(\.keyCode))
        #expect(codes.count == 8)
        #expect(codes.contains(Constants.defaultActivationKeyCode))  // 61, Right Option
    }

    @Test("Caps Lock is not a dictation key")
    func capsLockExcluded() {
        // Why: River's tap sees one event per Caps Lock press and none on release, so
        // Hold never sees the release and a tap mode needs two presses per tap. Offering
        // it would hand the user a key that cannot work in any mode.
        #expect(!ActivationKeyOption.all.contains { $0.keyCode == 57 })
    }

    @Test("fn is not a dictation key")
    func fnExcluded() {
        // Why: fn cancels a recording (spec 0036). As the dictation key its press would
        // have to start and stop instead, leaving a recording with no cancel key.
        #expect(!ActivationKeyOption.all.contains { $0.keyCode == Constants.cancelKeyCode })
    }
}

@Suite("Settings section")
struct SettingsSectionTests {
    // River can't dictate until every permission is granted, so a missing one takes the user
    // straight to it; a dictation shortcut that does nothing comes next; otherwise the window
    // reopens where they left it (planning 0036).
    @Test("the window opens on Permissions, then on a failing shortcut, else on the last section", arguments: SettingsSection.allCases)
    func openingSection(last: SettingsSection) {
        #expect(SettingsSection.opening(lastShown: last, permissionMissing: true, shortcutFailing: false) == .permissions)
        #expect(SettingsSection.opening(lastShown: last, permissionMissing: true, shortcutFailing: true) == .permissions)
        #expect(SettingsSection.opening(lastShown: last, permissionMissing: false, shortcutFailing: true) == .shortcuts)
        #expect(SettingsSection.opening(lastShown: last, permissionMissing: false, shortcutFailing: false) == last)
    }
}
