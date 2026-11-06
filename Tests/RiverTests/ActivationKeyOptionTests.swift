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
