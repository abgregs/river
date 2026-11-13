import Testing
@testable import River

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
