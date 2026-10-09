import AppKit
import Foundation
import Testing
@testable import River

/// The indicator's panel lifecycle against a real `NSPanel` (planning 0030). The Space loss
/// itself comes from the window server and can't be staged in a test, so this checks the
/// remedy: every recording orders in a panel that has never been on screen, which is
/// exactly what a relaunch provides. Panels are made fully transparent so nothing flashes.
@MainActor
@Suite("RecordingIndicatorCoordinator")
struct RecordingIndicatorCoordinatorTests {

    @Test("a panel that has been on screen is replaced after it fades out, so the next recording shows one that has not")
    func replacesShownPanelAfterOrderOut() async throws {
        let appState = AppState()
        appState.apply(modelLoadState: .ready)
        let coordinator = RecordingIndicatorCoordinator(appState: appState)
        coordinator.start()

        let first = try #require(coordinator.panel)
        first.alphaValue = 0
        appState.apply(.recording)
        try await waitForObservation()
        #expect(first.isVisible)

        appState.apply(.idle)
        try await Task.sleep(for: .seconds(Constants.hudFadeSeconds + 0.2))
        let second = try #require(coordinator.panel)
        // A reused panel keeps whatever Spaces the window server last left it on;
        // after a full-screen Space closed, that can be none at all.
        #expect(second !== first)
        #expect(!first.isVisible)
        #expect(!second.isVisible)

        second.alphaValue = 0
        appState.apply(.recording)
        try await waitForObservation()
        #expect(coordinator.panel === second)
        #expect(second.isVisible)
        appState.apply(.idle)
    }

    @Test("a panel that was never shown is kept, so the first recording still fades in from a prepared panel")
    func keepsUnshownPanel() async throws {
        let appState = AppState()
        appState.apply(modelLoadState: .ready)
        let coordinator = RecordingIndicatorCoordinator(appState: appState)
        coordinator.start()
        let first = try #require(coordinator.panel)

        try await Task.sleep(for: .seconds(Constants.hudFadeSeconds + 0.2))
        #expect(coordinator.panel === first)
    }

    // The coordinator re-reads `AppState` on a main-actor hop after each change.
    private func waitForObservation() async throws {
        try await Task.sleep(for: .milliseconds(50))
    }
}
