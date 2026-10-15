import Foundation

/// Pure mapping from cycle state to the menu-bar icon + status label, extracted
/// so the icon/label contract is unit-tested without standing up SwiftUI.
enum MenuBarPresentation {
    // The stones mark's menu bar glyphs (docs/design/stones-identity.md), shipped as PNGs in
    // the bundle's Resources. Ready is the r as a template image the system tints. Active,
    // for both Listening and Transcribing, is a frozen reading of the bars in the accent:
    // the accent means River is on. A colored image is not tinted by the system, so Active
    // ships one image per menu bar appearance.
    enum Glyph: String, CaseIterable {
        case ready = "MenuBarReady"
        case active = "MenuBarActive"

        var isTemplate: Bool { self == .ready }

        func assetName(dark: Bool) -> String {
            self == .active && dark ? "\(rawValue)Dark" : rawValue
        }

        // Every file `make bundle` copies and `make verify` asserts, without the scale suffix.
        static var assetNames: [String] {
            allCases.flatMap { glyph in glyph.isTemplate ? [glyph.rawValue] : [glyph.rawValue, glyph.assetName(dark: true)] }
        }
    }

    // The cycle states draw River's mark; the warning, downloading, and loading states keep
    // their SF Symbols.
    enum Icon: Equatable {
        case glyph(Glyph)
        case symbol(String)
    }

    struct Visual: Equatable {
        let icon: Icon
        let statusLabel: String
    }

    // core-feature.md item 5: Ready (.idle) shows the r; Listening (.recording) and
    // Transcribing (.processing) show the bars; labels "Ready" / "Recording..." / "Processing...".
    // A pending error overrides the *idle* icon with a warning glyph — errors
    // surface at end-of-cycle, so an active state's icon always wins.
    //
    // During the model load window (planning 0004), the idle state shows the load
    // progress ("Downloading model…" / "Preparing model…") instead of "Ready". Active cycle
    // states (.recording / .processing) are never masked — the model is ready before
    // recording is permitted, so the load state only affects the idle presentation.
    static func visual(state: RiverState, hasError: Bool, modelLoadState: ModelLoadState = .ready) -> Visual {
        // Non-idle states are unaffected by model load state.
        guard state == .idle else {
            let glyph: Glyph
            switch state {
            case .idle: glyph = .ready  // unreachable (guard above), kept for exhaustiveness
            case .recording, .processing: glyph = .active
            }
            let statusLabel: String
            switch state {
            case .idle: statusLabel = "Ready"
            case .recording: statusLabel = "Recording..."
            case .processing: statusLabel = "Processing..."
            }
            return Visual(icon: .glyph(glyph), statusLabel: statusLabel)
        }

        // Idle + model still loading: show download/load progress instead of "Ready".
        switch modelLoadState {
        case .downloading:
            return Visual(icon: .symbol("arrow.down.circle"), statusLabel: "Downloading model...")
        case .loading:
            return Visual(icon: .symbol("ellipsis"), statusLabel: "Preparing model...")
        case .failed:
            // "Ready" here would be the exact lie 0004 removes — dictation cannot
            // work until relaunch, so the label says so alongside the glyph. (The
            // session also emits a .transcription error if the user tries anyway.)
            return Visual(icon: .symbol("exclamationmark.triangle"), statusLabel: "Model failed to load")
        case .ready:
            let icon: Icon = hasError ? .symbol("exclamationmark.triangle") : .glyph(.ready)
            return Visual(icon: icon, statusLabel: "Ready")
        }
    }
}
