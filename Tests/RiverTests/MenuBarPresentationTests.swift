import Testing
@testable import River

@Suite("MenuBarPresentation")
struct MenuBarPresentationTests {
    // The icon/label contract is the user-visible half of requirement
    // core-feature.md item 5. These pin it so a symbol or copy change is a
    // deliberate edit with a failing test, not a silent drift.
    @Test("icon and label reflect each cycle state when model is ready")
    func visualPerState() {
        #expect(MenuBarPresentation.visual(state: .idle, hasError: false, modelLoadState: .ready)
            == .init(icon: .glyph(.ready), statusLabel: "Ready"))
        #expect(MenuBarPresentation.visual(state: .recording, hasError: false, modelLoadState: .ready)
            == .init(icon: .glyph(.listening), statusLabel: "Recording..."))
        #expect(MenuBarPresentation.visual(state: .processing, hasError: false, modelLoadState: .ready)
            == .init(icon: .glyph(.transcribing), statusLabel: "Processing..."))
    }

    @Test("a pending error overrides the idle icon but keeps the status label")
    func errorOverridesIdleIcon() {
        let visual = MenuBarPresentation.visual(state: .idle, hasError: true, modelLoadState: .ready)
        #expect(visual.icon == .symbol("exclamationmark.triangle"))
        #expect(visual.statusLabel == "Ready")
    }

    @Test("an active state's icon wins over a pending error")
    func activeStateIconWinsOverError() {
        // Errors surface at end-of-cycle; a recording/processing icon must not
        // be masked by a stale error from the previous cycle.
        #expect(MenuBarPresentation.visual(state: .recording, hasError: true, modelLoadState: .ready).icon == .glyph(.listening))
        #expect(MenuBarPresentation.visual(state: .processing, hasError: true, modelLoadState: .ready).icon == .glyph(.transcribing))
    }

    // MARK: - Load state mapping (planning 0004 AC4)

    @Test("while the model downloads, idle shows the ring's arc in eighths and the real percentage")
    func downloadingState() {
        // Cold launch: model files not yet on disk. The menu must show progress,
        // not "Ready" — "Ready" while the model is still downloading is a lie.
        let visual = MenuBarPresentation.visual(state: .idle, hasError: false, modelLoadState: .downloading, fraction: 0.62)
        let ring = MenuBarPresentation.Ring(phase: .downloading, eighths: 4)
        #expect(visual == .init(icon: .ring(ring), statusLabel: "Downloading model… 62%", statusRing: ring))
    }

    @Test("the menu bar's arc moves in eighths, so a download redraws the icon eight times at most")
    func downloadRedrawsInEighths() {
        let at = { MenuBarPresentation.Ring.of(.downloading, fraction: $0) }
        #expect(at(0.0) == at(0.12))
        #expect(at(0.12) != at(0.13))
        #expect(Set(stride(from: 0.0, through: 1, by: 0.001).compactMap(at)).count == 9)
    }

    @Test("while the model gets ready, idle shows the ring and says so")
    func loadingState() {
        // Warm launch: files on disk, CoreML loading into memory. Still not "Ready".
        let visual = MenuBarPresentation.visual(state: .idle, hasError: false, modelLoadState: .loading)
        #expect(visual.icon == .ring(.init(phase: .preparing, eighths: nil)))
        #expect(visual.statusLabel == "Getting the model ready…")
    }

    @Test("a failed load shows the ring with its sign and an honest label: the arc where a download stopped")
    func failedState() {
        // "Ready" after a failed load would be the exact menu-bar lie 0004 removes.
        let visual = MenuBarPresentation.visual(state: .idle, hasError: false, modelLoadState: .failed, fraction: 0.4)
        #expect(visual.icon == .ring(.init(phase: .failed, eighths: 3)))
        #expect(visual.statusLabel == "Couldn’t load the model")
        // A model that arrived but wouldn't load has no arc: the whole ring.
        #expect(MenuBarPresentation.visual(state: .idle, hasError: false, modelLoadState: .failed).icon
            == .ring(.init(phase: .failed, eighths: nil)))
    }

    @Test("a dictation waiting for the model says what it waits for, under the transcribing icon")
    func waitingDictationNamesTheModel() {
        // A dictation now starts before the model is ready (planning 0004), so "Processing..."
        // could mean minutes: the status line names the wait instead.
        let visual = MenuBarPresentation.visual(state: .processing, hasError: false, modelLoadState: .downloading, fraction: 0.3)
        #expect(visual.icon == .glyph(.transcribing))
        #expect(visual.statusLabel == "Downloading model… 30%")
        #expect(visual.statusRing == .init(phase: .downloading, eighths: 2))
    }

    @Test("the model's state never changes the recording or processing icon")
    func loadStateDoesNotAffectActiveStates() {
        // Active states are visible feedback during a live recording/paste cycle.
        // They must never be masked by the model load state.
        #expect(MenuBarPresentation.visual(state: .recording, hasError: false, modelLoadState: .loading).icon == .glyph(.listening))
        #expect(MenuBarPresentation.visual(state: .processing, hasError: false, modelLoadState: .loading).icon == .glyph(.transcribing))
        #expect(MenuBarPresentation.visual(state: .recording, hasError: false, modelLoadState: .downloading).icon == .glyph(.listening))
    }

    // The asset names are the contract with the bundle: `make verify` checks these files
    // ship, so a renamed case must fail here before it silently blanks the menu bar.
    @Test("the glyphs map to their shipped asset names")
    func glyphAssetNames() {
        #expect(MenuBarPresentation.Glyph.assetNames == ["MenuBarReady", "MenuBarWithDot"])
    }

    @Test("default modelLoadState is .ready (backward-compatible call sites)")
    func defaultModelLoadStateIsReady() {
        // `visual(state:hasError:)` callers that don't pass modelLoadState must
        // continue to work correctly after adding the parameter.
        #expect(MenuBarPresentation.visual(state: .idle, hasError: false)
            == .init(icon: .glyph(.ready), statusLabel: "Ready"))
    }
}
