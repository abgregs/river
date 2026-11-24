import AppKit
import CoreGraphics
import Foundation
import os

enum TextInsertionError: Error, LocalizedError {
    case noEditableTarget

    var errorDescription: String? {
        switch self {
        case .noEditableTarget:
            return "No text field focused — click into a text field and try again."
        }
    }
}

/// What a delivery did with its text: typed it all, or stopped and held it because the app it
/// was meant for left the front (planning 0004, 0039).
enum Delivery {
    case typed
    case held
}

@MainActor
final class TextInsertionManager {
    /// Waits between keystroke chunks. Injected so tests record the gaps instead of
    /// sleeping (the injectable-clock pattern of `TapStateMachine`).
    typealias Pause = @MainActor (_ seconds: Double) async -> Void
    /// The process ID of the app in front. Injected so tests pass a fixed one.
    typealias FrontmostApp = @MainActor () -> pid_t?

    private let accessibility: AccessibilityCapability
    private let pause: Pause
    private let frontmostApp: FrontmostApp
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "insert")
    // One delivery types at a time; the rest wait here, in order.
    private var isTyping = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(accessibility: AccessibilityCapability, pause: Pause? = nil, frontmostApp: FrontmostApp? = nil) {
        self.accessibility = accessibility
        self.pause = pause ?? { seconds in try? await Task.sleep(for: .seconds(seconds)) }
        self.frontmostApp = frontmostApp ?? { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    }

    /// The app in front now, by process ID: the session reads it at the release, and the
    /// delivery reads it again before each chunk, to type only into the app dictated into
    /// (planning 0004).
    func appInFront() -> pid_t? { frontmostApp() }

    /// Types `text` at the cursor as Unicode key events, after any delivery still typing — the
    /// app never touches the clipboard, so the clipboard-restore race is gone *by construction*
    /// (planning 0011). The keystrokes route through `AccessibilityCapability.postKeyEvent`,
    /// the one `CGEvent.post` site, so the `.granted` gate still applies. A newline is typed as
    /// a space: Return sends a message in most chat apps (planning 0039).
    ///
    /// Returns `.held` when `app` is not in front before a chunk, and stops there. Throws
    /// `TextInsertionError.noEditableTarget` when the focused element is clearly non-editable —
    /// the insertion guard (planning 0001).
    func deliver(_ text: String, to app: pid_t?) async throws -> Delivery {
        await waitForTurn()
        defer { endTurn() }
        // Before the guard, so a switch to an app with no text field holds the text rather
        // than reporting no field.
        if hasLeft(app) { return held(text) }
        // Insertion guard (planning 0001): typing into a non-editable target is
        // indistinguishable from success after the fact, so check the focused
        // element's role first. `.unknown` fails open — only a clearly
        // non-editable role skips.
        if accessibility.classifyFocusedTarget() == .nonEditable {
            logger.info("deliver: skipped — focused element is not editable")
            throw TextInsertionError.noEditableTarget
        }
        let chunks = Self.chunk(String(text.map { $0.isNewline ? " " : $0 }), maxUnits: Constants.keystrokeChunkUnits)
        logger.info("deliver: injecting \(text.count, privacy: .public) chars in \(chunks.count, privacy: .public) chunk(s)")
        do {
            for (index, chunk) in chunks.enumerated() {
                if index > 0 {
                    // Paced, so a terminal hands the target a few chunks per read rather than
                    // the whole transcript at once (planning 0031).
                    await pause(Constants.keystrokeChunkGapSeconds)
                    if hasLeft(app) { return held(text) }
                }
                try accessibility.postKeyEvent(Self.makeUnicodeKeyEvent(chunk, keyDown: true))
                try accessibility.postKeyEvent(Self.makeUnicodeKeyEvent(chunk, keyDown: false))
            }
            logger.info("deliver: done")
            return .typed
        } catch {
            // `postKeyEvent`'s `.notGranted`: on the first chunk nothing was typed, but a grant
            // lost during the pauses stops a delivery part-way. Rethrown for `RiverSession`.
            logger.error("deliver: failed: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
            throw error
        }
    }

    private func hasLeft(_ app: pid_t?) -> Bool {
        guard let app else { return false }
        return frontmostApp() != app
    }

    private func held(_ text: String) -> Delivery {
        logger.info("deliver: the app in front changed; holding \(text.count, privacy: .public) chars")
        return .held
    }

    // Not cancellable: a delivery that stopped waiting would type out of turn.
    private func waitForTurn() async {
        guard isTyping else {
            isTyping = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    // The turn passes straight to the next delivery in line, so none can cut in.
    private func endTurn() {
        if waiting.isEmpty { isTyping = false } else { waiting.removeFirst().resume() }
    }

    // internal for testability — splits `text` into chunks of at most `maxUnits`
    // UTF-16 code units without ever splitting a grapheme cluster, so surrogate
    // pairs and combining marks stay intact within a single event.
    // `keyboardSetUnicodeString` is unreliable past ~20 units in some apps, hence
    // the chunking; the post is exercised via `postedEventCountForTesting`.
    static func chunk(_ text: String, maxUnits: Int) -> [String] {
        guard maxUnits > 0 else { return text.isEmpty ? [] : [text] }
        var chunks: [String] = []
        var current = ""
        var currentUnits = 0
        for character in text {                 // Character == grapheme cluster
            let units = String(character).utf16.count
            if currentUnits + units > maxUnits, !current.isEmpty {
                chunks.append(current)
                current = ""
                currentUnits = 0
            }
            current.append(character)
            currentUnits += units
        }
        if !current.isEmpty { chunks.append(current) }
        return balancedEnding(chunks, maxUnits: maxUnits)
    }

    // A target can take a lone character at once while it still holds earlier chunks back as
    // a possible paste, so a last chunk of one character landed early in Claude Code (planning
    // 0031): the last two chunks share their characters instead, within the unit budget.
    private static func balancedEnding(_ chunks: [String], maxUnits: Int) -> [String] {
        guard chunks.count >= 2, chunks[chunks.count - 1].count == 1 else { return chunks }
        var front = Array(chunks[chunks.count - 2])
        var back = Array(chunks[chunks.count - 1])
        var backUnits = back.reduce(0) { $0 + String($1).utf16.count }
        while front.count - back.count >= 2, let moving = front.last,
              backUnits + String(moving).utf16.count <= maxUnits {
            back.insert(front.removeLast(), at: 0)
            backUnits += String(moving).utf16.count
        }
        return Array(chunks.dropLast(2)) + [String(front), String(back)]
    }

    // Builds a key event carrying the literal characters. `keyboardSetUnicodeString`
    // overrides the virtual key, so the keycode (0) is a placeholder. The string
    // is set on both the down and up events (the common pattern); apps insert on
    // key-down and ignore the up's string. Force-unwrap matches the CGEvent /
    // AVAudioFormat pattern elsewhere — the init only returns nil for an invalid
    // keycode, and 0 is valid.
    private static func makeUnicodeKeyEvent(_ string: String, keyDown: Bool) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: keyDown)!
        let utf16 = Array(string.utf16)
        event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        return event
    }
}
