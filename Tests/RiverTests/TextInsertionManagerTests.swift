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

    @MainActor
    @Test("a plan never ends on a lone character: the last two chunks share the remainder")
    func lastChunkIsNeverOneCharacter() {
        // Claude Code's prompt took a final one-character chunk at once, ahead of chunks it
        // still held as a possible paste, so the last character landed early (planning 0031).
        let a = { (count: Int) in String(repeating: "a", count: count) }
        #expect(TextInsertionManager.chunk(a(21), maxUnits: 20).map(\.count) == [11, 10])
        #expect(TextInsertionManager.chunk(a(41), maxUnits: 20).map(\.count) == [20, 11, 10])
        #expect(TextInsertionManager.chunk(a(421), maxUnits: 20).map(\.count) == Array(repeating: 20, count: 20) + [11, 10])
        #expect(TextInsertionManager.chunk(a(22), maxUnits: 20).map(\.count) == [20, 2])
        let flag = "\u{1F1FA}\u{1F1F8}"   // one character, four UTF-16 units
        #expect(TextInsertionManager.chunk(a(20) + flag, maxUnits: 20) == [a(11), a(9) + flag])
        #expect(TextInsertionManager.chunk("a", maxUnits: 20) == ["a"])
    }

    @MainActor
    @Test("every plan keeps the text whole, its characters intact, its chunks in budget and none alone", arguments: [
        "a", "漢", "e\u{301}", "\u{1F44D}\u{1F3FD}", "\u{1F1FA}\u{1F1F8}", "\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}", "word ",
    ])
    func everyPlanHolds(unit: String) {
        for count in 2...100 {
            let text = String(repeating: unit, count: count)
            let chunks = TextInsertionManager.chunk(text, maxUnits: 20)
            #expect(chunks.joined() == text)
            // A character split across chunks would count twice.
            #expect(chunks.map(\.count).reduce(0, +) == text.count)
            #expect(chunks.allSatisfy { $0.utf16.count <= 20 })
            #expect(chunks.allSatisfy { $0.count >= 2 }, "\(count) × \(unit): \(chunks.map(\.count))")
        }
    }
}

@Suite("TextInsertionManager.deliver")
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
        #expect(try await manager.deliver(String(repeating: "x", count: 50), to: nil) == .typed)
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

        #expect(try await manager.deliver("hi", to: nil) == .typed)          // 1 chunk → 2 events
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
            _ = try await manager.deliver("transcribed", to: nil)
        }
        #expect(accessibility.postedEventCountForTesting == 0)
    }

    @MainActor
    @Test("not-granted capability throws before injecting")
    func throwsWhenNotGranted() async {
        // With status `.denied`, the focus read fails open to `.unknown` (not
        // non-editable), so the delivery proceeds to the first post — which
        // `postKeyEvent` refuses with `.notGranted`. No partial injection.
        let accessibility = AccessibilityCapability()
        accessibility.setStatusForTesting(.denied)
        let manager = TextInsertionManager(accessibility: accessibility)

        await #expect(throws: AccessibilityCapabilityError.self) {
            _ = try await manager.deliver("transcribed", to: nil)
        }
    }

    @MainActor
    @Test("two deliveries never mix: the second waits for the first to finish")
    func deliveriesTakeTurns() async throws {
        let accessibility = AccessibilityCapability()
        accessibility.skipPostForTesting = true
        accessibility.setStatusForTesting(.granted)
        accessibility.focusedTargetForTesting = .editable
        // Each pause lets other work run, as a real one does, so a delivery that didn't wait
        // its turn would slip its chunks between the first one's (planning 0039).
        let manager = TextInsertionManager(accessibility: accessibility, pause: { _ in await Task.yield() })
        let a = String(repeating: "a", count: 50), b = String(repeating: "b", count: 50)
        let first = Task { @MainActor in try await manager.deliver(a, to: nil) }
        let second = Task { @MainActor in try await manager.deliver(b, to: nil) }
        #expect(try await first.value == .typed)
        #expect(try await second.value == .typed)
        let typed = accessibility.postedKeyDownTextForTesting.joined()
        #expect(typed == a + b || typed == b + a)
    }

    @MainActor
    @Test("deliveries waiting their turn type in the order they arrived", .timeLimit(.minutes(1)))
    func waitingDeliveriesKeepTheirOrder() async throws {
        // Two Paste last presses behind a long insert must type in the order pressed. The first
        // holds the turn until both others are waiting, so the turn's hand-off decides the order.
        let accessibility = AccessibilityCapability()
        accessibility.skipPostForTesting = true
        accessibility.setStatusForTesting(.granted)
        accessibility.focusedTargetForTesting = .editable
        var held: CheckedContinuation<Void, Never>?
        var pauses = 0
        let manager = TextInsertionManager(accessibility: accessibility, pause: { _ in
            pauses += 1
            if pauses == 1 { await withCheckedContinuation { held = $0 } } else { await Task.yield() }
        })
        let a = String(repeating: "a", count: 50), b = String(repeating: "b", count: 50), c = String(repeating: "c", count: 50)

        let first = Task { @MainActor in try await manager.deliver(a, to: nil) }
        for _ in 0..<200 where held == nil { await Task.yield() }
        let second = Task { @MainActor in try await manager.deliver(b, to: nil) }
        let third = Task { @MainActor in try await manager.deliver(c, to: nil) }
        for _ in 0..<20 { await Task.yield() }
        held?.resume()
        _ = try await (first.value, second.value, third.value)
        #expect(accessibility.postedKeyDownTextForTesting.joined() == a + b + c)
    }

    @MainActor
    @Test("a delivery that fails part-way still passes its turn to the next", .timeLimit(.minutes(1)))
    func failurePassesTheTurn() async throws {
        let accessibility = AccessibilityCapability()
        accessibility.skipPostForTesting = true
        accessibility.setStatusForTesting(.granted)
        accessibility.focusedTargetForTesting = .editable
        var paused: CheckedContinuation<Void, Never>?
        let manager = TextInsertionManager(accessibility: accessibility, pause: { _ in
            await withCheckedContinuation { paused = $0 }
        }, frontmostApp: { 100 })

        let first = Task { @MainActor in try await manager.deliver(String(repeating: "a", count: 50), to: nil) }
        for _ in 0..<200 where paused == nil { await Task.yield() }
        // The second waits its turn behind the first, which loses its grant mid-way; a turn
        // never passed on would leave it waiting until the time limit fails the test.
        let second = Task { @MainActor in try await manager.deliver("b", to: 200) }
        await Task.yield()
        accessibility.setStatusForTesting(.denied)
        paused?.resume()
        await #expect(throws: AccessibilityCapabilityError.self) { _ = try await first.value }
        #expect(try await second.value == .held)
    }

    @MainActor
    @Test("a switch of app while River types stops it and holds the text")
    func appSwitchMidInsertHolds() async throws {
        let accessibility = AccessibilityCapability()
        accessibility.skipPostForTesting = true
        accessibility.setStatusForTesting(.granted)
        accessibility.focusedTargetForTesting = .editable
        var front: pid_t = 100
        let manager = TextInsertionManager(accessibility: accessibility, pause: { _ in front = 200 }, frontmostApp: { front })

        #expect(try await manager.deliver(String(repeating: "a", count: 50), to: 100) == .held)
        // Only the chunk typed before the switch: the rest never reaches the other app.
        #expect(accessibility.postedKeyDownTextForTesting == [String(repeating: "a", count: 20)])
    }

    @MainActor
    @Test("a switch to an app with no text field holds the text rather than reporting no field")
    func appSwitchBeforeTheGuardHolds() async throws {
        let accessibility = AccessibilityCapability()
        accessibility.skipPostForTesting = true
        accessibility.setStatusForTesting(.granted)
        accessibility.focusedTargetForTesting = .nonEditable
        let manager = TextInsertionManager(accessibility: accessibility, frontmostApp: { 200 })

        #expect(try await manager.deliver("transcribed", to: 100) == .held)
        #expect(accessibility.postedEventCountForTesting == 0)
    }

    @MainActor
    @Test("a delivery its caller stops while it waits its turn types nothing", .timeLimit(.minutes(1)))
    func stoppedWhileWaiting() async throws {
        // A Paste last queued behind another must not type once a dictation has started: its keys
        // would land under the held dictation key (spec 0036).
        let accessibility = AccessibilityCapability()
        accessibility.skipPostForTesting = true
        accessibility.setStatusForTesting(.granted)
        accessibility.focusedTargetForTesting = .editable
        var paused: CheckedContinuation<Void, Never>?
        let manager = TextInsertionManager(accessibility: accessibility, pause: { _ in
            if paused == nil { await withCheckedContinuation { paused = $0 } }
        })
        var canType = true
        let a = String(repeating: "a", count: 50)

        let first = Task { @MainActor in try await manager.deliver(a, to: nil) }
        for _ in 0..<200 where paused == nil { await Task.yield() }
        let second = Task { @MainActor in try await manager.deliver("b", to: nil, while: { canType }) }
        await Task.yield()
        canType = false
        paused?.resume()
        #expect(try await first.value == .typed)
        #expect(try await second.value == .held)
        #expect(accessibility.postedKeyDownTextForTesting.joined() == a)
    }

    @MainActor
    @Test("a delivery its caller stops part-way types no further chunk")
    func stoppedPartWay() async throws {
        // A Paste last already typing stops when a dictation starts, as it does for a switch of app.
        let accessibility = AccessibilityCapability()
        accessibility.skipPostForTesting = true
        accessibility.setStatusForTesting(.granted)
        accessibility.focusedTargetForTesting = .editable
        var canType = true
        let manager = TextInsertionManager(accessibility: accessibility, pause: { _ in canType = false })

        #expect(try await manager.deliver(String(repeating: "a", count: 50), to: nil, while: { canType }) == .held)
        #expect(accessibility.postedKeyDownTextForTesting == [String(repeating: "a", count: 20)])
    }

    @MainActor
    @Test("a newline is typed as a space, so it never sends a message")
    func newlineIsTypedAsSpace() async throws {
        let accessibility = AccessibilityCapability()
        accessibility.skipPostForTesting = true
        accessibility.setStatusForTesting(.granted)
        accessibility.focusedTargetForTesting = .editable
        let manager = TextInsertionManager(accessibility: accessibility, pause: { _ in })

        #expect(try await manager.deliver("a\nb\r\nc\u{2028}d", to: nil) == .typed)
        #expect(accessibility.postedKeyDownTextForTesting.joined() == "a b c d")
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

        #expect(try await manager.deliver(Self.transcript, to: nil) == .typed)
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

        #expect(try await manager.deliver(Self.transcript, to: nil) == .typed)
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

        #expect(try await manager.deliver("short", to: nil) == .typed)
        #expect(pauses == 0)
        #expect(accessibility.postedKeyDownTextForTesting == ["short"])
    }
}
