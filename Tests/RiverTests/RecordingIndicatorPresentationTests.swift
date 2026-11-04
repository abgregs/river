import Testing
@testable import River

@Suite("RecordingIndicatorPresentation")
struct RecordingIndicatorPresentationTests {
    @Test("recording and processing are on screen; idle without a toast is not")
    func visibilityPerState() {
        #expect(RecordingIndicatorPresentation.isOnScreen(state: .recording, hasToast: false, modelLoadState: .ready))
        #expect(RecordingIndicatorPresentation.isOnScreen(state: .processing, hasToast: false, modelLoadState: .ready))
        #expect(!RecordingIndicatorPresentation.isOnScreen(state: .idle, hasToast: false, modelLoadState: .ready))
    }

    @Test("a pending toast keeps the panel on screen at idle")
    func toastKeepsPanelVisibleAtIdle() {
        // Errors surface at end-of-cycle, when the state has already returned to
        // .idle. If the panel dropped the moment state hit .idle, the toast would
        // never be seen. The toast must outlive the recording that triggered it.
        #expect(RecordingIndicatorPresentation.isOnScreen(state: .idle, hasToast: true, modelLoadState: .ready))
    }

    @Test("an in-flight model load shows the panel at idle — the HUD is the primary loading surface")
    func loadingShowsPanelAtIdle() {
        // The loading wait must surface proactively in the HUD, not only via a
        // declined activation; the menu bar label is the secondary sync.
        #expect(RecordingIndicatorPresentation.isOnScreen(state: .idle, hasToast: false, modelLoadState: .downloading))
        #expect(RecordingIndicatorPresentation.isOnScreen(state: .idle, hasToast: false, modelLoadState: .loading))
    }

    @Test("a failed load does not pin the panel on screen — failed stays menu-only")
    func failedDoesNotPinPanel() {
        // .failed is permanent until relaunch; a floating panel that never leaves
        // would nag. Its recovery UX is a recorded follow-up (model-switch spec).
        #expect(!RecordingIndicatorPresentation.isOnScreen(state: .idle, hasToast: false, modelLoadState: .failed))
    }

    @Test("loadingLabel names the two waiting states and nothing else")
    func loadingLabelMapping() {
        #expect(RecordingIndicatorPresentation.loadingLabel(for: .downloading) == "Downloading model…")
        #expect(RecordingIndicatorPresentation.loadingLabel(for: .loading) == "Preparing model…")
        #expect(RecordingIndicatorPresentation.loadingLabel(for: .ready) == nil)
        #expect(RecordingIndicatorPresentation.loadingLabel(for: .failed) == nil)
    }
}
