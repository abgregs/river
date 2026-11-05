import Foundation

/// Pure mapping from cycle state to the menu-bar icon + status label, extracted
/// so the icon/label contract is unit-tested without standing up SwiftUI.
enum MenuBarPresentation {
    // The mark's menu bar glyphs (docs/design/kawa-identity.md): Ready is 川; Listening is 川
    // with the red recording dot; Transcribing the same dot in muted ink. They ship as two PNGs
    // in the bundle's Resources, template images the system paints white or black to match the
    // menu bar, as it does every other icon there: 川 alone, and 川 beside the dot's place, over
    // which River draws the dot.
    enum Glyph: CaseIterable {
        case ready, listening, transcribing

        var assetName: String { self == .ready ? "MenuBarReady" : "MenuBarWithDot" }

        // Every file `make bundle` copies and `make verify` asserts, without the scale suffix.
        static var assetNames: [String] {
            allCases.map(\.assetName).reduce(into: []) { names, name in if !names.contains(name) { names.append(name) } }
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

    // core-feature.md item 5: Ready (.idle) shows 川; Listening (.recording) adds the red dot;
    // Transcribing (.processing) the muted dot; labels "Ready" / "Recording..." / "Processing...".
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
            case .recording: glyph = .listening
            case .processing: glyph = .transcribing
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
