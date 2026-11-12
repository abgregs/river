import Testing
@testable import River

@Suite("ActivationKeyOption")
struct ActivationKeyOptionTests {
    @Test("table lists the 9 supported keys, no duplicate keycodes, includes the default")
    func tableComplete() {
        #expect(ActivationKeyOption.all.count == 9)
        let codes = Set(ActivationKeyOption.all.map(\.keyCode))
        #expect(codes.count == 9)
        #expect(codes.contains(Constants.defaultActivationKeyCode))  // 61, Right Option
    }

    @Test("Caps Lock is not a dictation key")
    func capsLockExcluded() {
        // Why: River's tap sees one event per Caps Lock press and none on release, so
        // Hold never sees the release and a tap mode needs two presses per tap. Offering
        // it would hand the user a key that cannot work in any mode.
        #expect(!ActivationKeyOption.all.contains { $0.keyCode == 57 })
    }
}

@Suite("Settings cancel line")
struct SettingsCancelLineTests {
    // fn is the cancel gesture, so with fn as the activation key the line must not promise it
    // (planning 0036, Cancel line): the menu item is the way left until Esc lands in PR 9.
    @Test("the cancel line names fn, unless fn alone starts dictation")
    func cancelLineFollowsTheShortcut() {
        #expect(ActivationKeyOption.cancelLine(for: .modifier(keyCode: 61)).contains("fn"))
        #expect(ActivationKeyOption.cancelLine(for: .combination(keyCode: 49, modifiers: [.control, .option])).contains("fn"))
        let fnLine = ActivationKeyOption.cancelLine(for: .modifier(keyCode: Constants.cancelKeyCode))
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
