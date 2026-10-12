import Foundation
import Testing
@testable import River

@Suite("TextInsertionManager.chunk")
struct TextInsertionChunkTests {
    // The chunker is the one piece of insertion logic that's pure and CI-testable
    // (the real `CGEvent.post` can't fire in CI). Its contract: never exceed the
    // unit budget, and never split a grapheme cluster (so emoji/combining marks
    // stay intact in a single event).

    @MainActor
    @Test("short text is a single chunk")
    func shortTextSingleChunk() {
        #expect(TextInsertionManager.chunk("hello world", maxUnits: 20) == ["hello world"])
    }

    @MainActor
    @Test("text longer than the budget splits into multiple chunks")
    func splitsOnBudget() {
        // 25 'a' with a budget of 10 → 10 + 10 + 5.
        let chunks = TextInsertionManager.chunk(String(repeating: "a", count: 25), maxUnits: 10)
        #expect(chunks == ["aaaaaaaaaa", "aaaaaaaaaa", "aaaaa"])
        #expect(chunks.allSatisfy { $0.utf16.count <= 10 })
    }

    @MainActor
    @Test("never splits a surrogate pair across chunks")
    func keepsGraphemesIntact() {
        // Each emoji is 2 UTF-16 units. With a budget of 3, two emoji (4 units)
        // must land in separate chunks rather than splitting the second's pair.
        let chunks = TextInsertionManager.chunk("👍👍", maxUnits: 3)
        #expect(chunks == ["👍", "👍"])
    }

    @MainActor
    @Test("empty text yields no chunks")
    func emptyYieldsNothing() {
        #expect(TextInsertionManager.chunk("", maxUnits: 20).isEmpty)
    }
}

@Suite("TextInsertionManager.insertText")
struct TextInsertionManagerTests {
    // No clipboard is touched, so these tests need no `NSPasteboard` setup and the
    // suite isn't `.serialized`. `skipPostForTesting` keeps the real `CGEvent.post`
    // from firing into the test runner's session; `postedEventCountForTesting`
    // counts the events the capability was asked to post (down+up per chunk).

    @MainActor
    @Test("editable target posts a down+up pair per chunk")
    func postsPerChunk() async throws {
        let accessibility = AccessibilityCapability()
        accessibility.skipPostForTesting = true
        accessibility.setStatusForTesting(.granted)
        accessibility.focusedTargetForTesting = .editable
        let manager = TextInsertionManager(accessibility: accessibility)

        // 50 chars at 20 units/chunk → 3 chunks → 6 events (down+up each).
        try await manager.insertText(String(repeating: "x", count: 50))
        #expect(accessibility.postedEventCountForTesting == 6)
    }

    @MainActor
    @Test("unknown focus fails open and still injects", arguments: [
        FocusedTargetClassification.unknown, FocusedTargetClassification.editable
    ])
    func failsOpenForUnknownOrEditable(classification: FocusedTargetClassification) async throws {
        // An undeterminable role must behave like editable (fail OPEN) — failing
        // closed would regress dictation in apps with poor AX exposure.
        let accessibility = AccessibilityCapability()
        accessibility.skipPostForTesting = true
        accessibility.setStatusForTesting(.granted)
        accessibility.focusedTargetForTesting = classification
        let manager = TextInsertionManager(accessibility: accessibility)

        try await manager.insertText("hi")          // 1 chunk → 2 events
        #expect(accessibility.postedEventCountForTesting == 2)
    }

    @MainActor
    @Test("non-editable target injects nothing and throws")
    func skipsNonEditableTarget() async {
        // The insertion guard (planning 0001): a clearly non-editable target gets
        // NO keystrokes. The throw is what surfaces "No text field focused" via
        // RiverSession.errors.
        let accessibility = AccessibilityCapability()
        accessibility.skipPostForTesting = true
        accessibility.setStatusForTesting(.granted)
        accessibility.focusedTargetForTesting = .nonEditable
        let manager = TextInsertionManager(accessibility: accessibility)

        await #expect(throws: TextInsertionError.self) {
            try await manager.insertText("transcribed")
        }
        #expect(accessibility.postedEventCountForTesting == 0)
    }

    @MainActor
    @Test("not-granted capability throws before injecting")
    func throwsWhenNotGranted() async {
        // With status `.denied`, the focus read fails open to `.unknown` (not
        // non-editable), so insertText proceeds to the first post — which
        // `postKeyEvent` refuses with `.notGranted`. No partial injection.
        let accessibility = AccessibilityCapability()
        accessibility.setStatusForTesting(.denied)
        let manager = TextInsertionManager(accessibility: accessibility)

        await #expect(throws: AccessibilityCapabilityError.self) {
            try await manager.insertText("transcribed")
        }
    }
}

@Suite("TextInsertionManager fidelity and pacing")
struct TextInsertionFidelityTests {
    // A long transcript posted back to back reached Claude Code's TUI as one burst: it
    // split the burst into unmarked "pastes" and dropped about 2 KB of a 3,000-character
    // insert (planning 0031). These pin the two halves of the fix: every character is
    // typed, in order, and consecutive chunks are spaced out.

    // Long prose with the characters most likely to break at a chunk boundary: emoji
    // (surrogate pairs), a combining accent, and punctuation.
    static let transcript: String = {
        let sentence = "River typed this, word for word: café, naïve 👍🏽, and \"quotes\" — every one. "
        return String(repeating: sentence, count: 40)
    }()

    @MainActor
    @Test("the typed text is the whole transcript, in order")
    func typesEveryCharacter() async throws {
        let accessibility = AccessibilityCapability()
        accessibility.skipPostForTesting = true
        accessibility.setStatusForTesting(.granted)
        accessibility.focusedTargetForTesting = .editable
        let manager = TextInsertionManager(accessibility: accessibility, pause: { _ in })

        try await manager.insertText(Self.transcript)
        #expect(accessibility.postedKeyDownTextForTesting.joined() == Self.transcript)
    }

    @MainActor
    @Test("chunks are spaced out, so no target receives the transcript as one burst")
    func pacesChunks() async throws {
        let accessibility = AccessibilityCapability()
        accessibility.skipPostForTesting = true
        accessibility.setStatusForTesting(.granted)
        accessibility.focusedTargetForTesting = .editable
        // Each pause records how many events were posted before it, which shows the
        // pauses fall between chunks: never before the first, never after the last.
        var postedAtPause: [Int] = []
        var gaps: [Double] = []
        let manager = TextInsertionManager(accessibility: accessibility, pause: { seconds in
            gaps.append(seconds)
            postedAtPause.append(accessibility.postedEventCountForTesting)
        })

        try await manager.insertText(Self.transcript)
        let chunks = TextInsertionManager.chunk(Self.transcript, maxUnits: Constants.keystrokeChunkUnits).count
        #expect(gaps.count == chunks - 1)
        #expect(postedAtPause == (1..<chunks).map { $0 * 2 })
        // 1 ms was the smallest gap that kept Claude Code lossless in every run.
        #expect(gaps.allSatisfy { $0 >= 0.001 })
    }

    @MainActor
    @Test("a single chunk is typed without any pause")
    func shortTextHasNoPause() async throws {
        let accessibility = AccessibilityCapability()
        accessibility.skipPostForTesting = true
        accessibility.setStatusForTesting(.granted)
        accessibility.focusedTargetForTesting = .editable
        var pauses = 0
        let manager = TextInsertionManager(accessibility: accessibility, pause: { _ in pauses += 1 })

        try await manager.insertText("short")
        #expect(pauses == 0)
        #expect(accessibility.postedKeyDownTextForTesting == ["short"])
    }
}
