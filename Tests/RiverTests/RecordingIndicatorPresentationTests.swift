import AppKit
import Testing
@testable import River

@Suite("RecordingIndicatorPresentation")
struct RecordingIndicatorPresentationTests {
    @Test("recording and processing are on screen; idle without a toast or a status is not")
    func visibilityPerState() {
        #expect(RecordingIndicatorPresentation.isOnScreen(state: .recording, hasToast: false, hasStatus: false))
        #expect(RecordingIndicatorPresentation.isOnScreen(state: .processing, hasToast: false, hasStatus: false))
        #expect(!RecordingIndicatorPresentation.isOnScreen(state: .idle, hasToast: false, hasStatus: false))
    }

    @Test("a pending toast keeps the panel on screen at idle")
    func toastKeepsPanelVisibleAtIdle() {
        // Errors surface at end-of-cycle, when the state has already returned to
        // .idle. If the panel dropped the moment state hit .idle, the toast would
        // never be seen. The toast must outlive the recording that triggered it.
        #expect(RecordingIndicatorPresentation.isOnScreen(state: .idle, hasToast: true, hasStatus: false))
    }

    @Test("a status that holds the panel keeps it on screen at idle")
    func statusKeepsPanelVisibleAtIdle() {
        // planning 0004: a failed load and held text are said once the dictation has ended,
        // when River is already idle, and stay 4 s. The panel must outlast the dictation for them.
        #expect(RecordingIndicatorPresentation.isOnScreen(state: .idle, hasToast: false, hasStatus: true))
    }
}

@Suite("Status row words")
struct StatusRowWordsTests {
    // planning 0004's words: the row says why the text hasn't typed yet.
    private static let pasteLast = (display: "⌃⌥V", spoken: "Control-Option-V")
    private static let downloadingAt = { (fraction: Double) in
        StatusRingFrame(layers: [.init(opacity: 1, marks: StatusRing.download(fraction, breath: 0))], akane: 0)
    }

    @Test("each status says why the text hasn't typed yet")
    func wordsPerStatus() {
        let downloading = StatusRowWords.of(.model(.downloading), frame: Self.downloadingAt(0.62), pasteLast: Self.pasteLast)
        #expect(downloading.main == "Typing after model download")
        #expect(downloading.detail == "62%")
        #expect(StatusRowWords.of(.model(.preparing), frame: nil, pasteLast: Self.pasteLast).main == "Typing once model is ready")
        #expect(StatusRowWords.of(.model(.ready), frame: nil, pasteLast: Self.pasteLast).main == "Ready")
        let failed = StatusRowWords.of(.model(.failed), frame: StatusRingFrame(layers: [], akane: 1), pasteLast: Self.pasteLast)
        #expect(failed.main == "Couldn’t load the model")
        #expect(failed.detail == "Recording kept")
    }

    @Test("the percentage counts with the arc and never claims 100 % before the download is done")
    func percentageFollowsTheArc() {
        #expect(StatusRowWords.of(.model(.downloading), frame: Self.downloadingAt(0.995), pasteLast: Self.pasteLast).detail == "99%")
        #expect(StatusRowWords.of(.model(.downloading), frame: Self.downloadingAt(0.3), pasteLast: Self.pasteLast).detail == "30%")
    }

    @Test("a failure keeps the words it had until the ring has half turned akane")
    func failureWordsFollowTheRing() {
        // The words change with the colour, so the row never says "couldn't load" over a ring
        // that hasn't turned yet.
        let turning = StatusRingFrame(layers: [.init(opacity: 1, marks: StatusRing.download(0.4, breath: 0))], akane: 0.3)
        #expect(StatusRowWords.of(.model(.failed), frame: turning, pasteLast: Self.pasteLast).main == "Typing after model download")
        let turned = StatusRingFrame(layers: turning.layers, akane: 0.6)
        #expect(StatusRowWords.of(.model(.failed), frame: turned, pasteLast: Self.pasteLast).main == "Couldn’t load the model")
    }

    @Test("held text names the Paste last shortcut, or the menu when the shortcut doesn't work")
    func heldWords() {
        let held = StatusRowWords.of(.held, frame: nil, pasteLast: Self.pasteLast)
        #expect(held.main == "App switched")
        #expect(held.detail == "⌃⌥V pastes it")
        #expect(held.spoken == "App switched. Control-Option-V pastes it.")
        #expect(StatusRowWords.of(.held, frame: nil, pasteLast: nil).detail == "Copy it from the menu")
    }

    @Test("VoiceOver hears each change of status, never a percentage")
    func spokenWordsHaveNoPercentage() {
        let spoken = StatusRowWords.of(.model(.downloading), frame: Self.downloadingAt(0.62), pasteLast: Self.pasteLast).spoken
        #expect(spoken == "Typing after model download")
        #expect(StatusRowWords.of(.model(.downloading), frame: Self.downloadingAt(0.7), pasteLast: Self.pasteLast).spoken == spoken)
    }

    @Test("the window is wide enough for the widest row on each side of the mark")
    @MainActor
    func widestRowFits() {
        // A row wider than the room the window keeps beside the mark would be cut off at its
        // edge. Measured as the row lays out: tile and words, the detail, then the end.
        typealias C = Constants
        let font = NSFont.systemFont(ofSize: C.statusRowFontSize)
        func width(_ text: String) -> Double { NSAttributedString(string: text, attributes: [.font: font]).size().width }
        // The longest Paste last shortcut River's recorder can save: every modifier and a named key.
        let longest = (display: ShortcutText.display(.combination(keyCode: 51, modifiers: [.control, .option, .shift, .command])),
                       spoken: "")
        let rows = StatusRowWords.all(pasteLast: longest)
        let leading: Double = C.statusRowPadding + C.statusRowTile + C.statusRowTextGap
        let widest = rows.map { words in
            leading + width(words.main)
                + (words.detail.map { C.statusRowDetailGap + width($0.hasSuffix("%") ? "100%" : $0) } ?? 0)
                + C.statusRowTrailingPadding
        }.max() ?? 0
        #expect(widest <= C.statusRowMaxWidth)
        #expect(RiverIndicatorView.contentSize.width / 2 >= C.indicatorPanelWidth / 2 + C.statusRowGap + C.statusRowMaxWidth)
    }
}
