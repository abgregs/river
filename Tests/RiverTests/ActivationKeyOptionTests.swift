import Testing
@testable import River

@Suite("ActivationKeyOption")
struct ActivationKeyOptionTests {
    @Test("table lists all 10 supported keys, no duplicate keycodes, includes the default")
    func tableComplete() {
        #expect(ActivationKeyOption.all.count == 10)
        let codes = Set(ActivationKeyOption.all.map(\.keyCode))
        #expect(codes.count == 10)
        #expect(codes.contains(Settings.activationKeyCode.defaultValue))  // 61, Right Option
    }

    @Test("Caps Lock + Hold warns; other keys and tap modes do not")
    func capsLockWarning() {
        // Why: Hold mode is broken on Caps Lock (it toggles on press, not held).
        // The inline warning is the inform-don't-block surface; if it stops firing
        // the user gets a silently broken hotkey (supported-keys-and-limitations.md).
        // The tap modes fire on key-up edges and work fine on Caps Lock — so the
        // warning is specific to the Hold pairing.
        let capsLock = ActivationKeyOption.capsLockKeyCode
        let warning = ActivationKeyOption.capsLockHoldWarning(keyCode: capsLock, mode: .hold)
        #expect(warning != nil)
        #expect(warning?.contains("Hold mode") == true)
        #expect(ActivationKeyOption.capsLockHoldWarning(keyCode: 61, mode: .hold) == nil)  // Right Option
        #expect(ActivationKeyOption.capsLockHoldWarning(keyCode: capsLock, mode: .singleTap) == nil)
        #expect(ActivationKeyOption.capsLockHoldWarning(keyCode: capsLock, mode: .doubleTap) == nil)
    }
}

@Suite("Settings cancel line")
struct SettingsCancelLineTests {
    // fn is the cancel gesture, so with fn as the activation key the line must not promise it
    // (planning 0036, Cancel line): the menu item is the way left until Esc lands in PR 9.
    @Test("the cancel line names fn, unless fn starts dictation")
    func cancelLineFollowsTheKey() {
        #expect(ActivationKeyOption.cancelLine(keyCode: 61).contains("fn"))
        let fnLine = ActivationKeyOption.cancelLine(keyCode: Constants.cancelKeyCode)
        #expect(!fnLine.contains("fn"))
        #expect(fnLine.contains("menu"))
    }
}

@Suite("Settings section")
struct SettingsSectionTests {
    // River can't dictate until every permission is granted, so a missing one takes the user
    // straight to it; otherwise the window reopens where they left it (planning 0036).
    @Test("the window opens on Permissions while one is missing, else on the last section", arguments: SettingsSection.allCases)
    func openingSection(last: SettingsSection) {
        #expect(SettingsSection.opening(lastShown: last, permissionMissing: true) == .permissions)
        #expect(SettingsSection.opening(lastShown: last, permissionMissing: false) == last)
    }
}
