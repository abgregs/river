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

    /// The model's status ring (planning 0004), still and in one tone in the menu bar: the
    /// download's arc in eighths, so the icon redraws eight times at most over a download; the
    /// ring while the model gets ready; the ring with an exclamation mark once it couldn't load.
    struct Ring: Hashable {
        let phase: StatusRing.Phase
        /// Eighths of the download, for downloading and a failed download; nil for a ring
        /// with no download to show.
        let eighths: Int?

        static func of(_ state: ModelLoadState, fraction: Double?) -> Ring? {
            let eighths = fraction.map { Int((min(max($0, 0), 1) * 8).rounded(.down)) }
            switch state {
            case .downloading: return Ring(phase: .downloading, eighths: eighths ?? 0)
            case .loading: return Ring(phase: .preparing, eighths: nil)
            case .failed: return Ring(phase: .failed, eighths: eighths)
            case .ready: return nil
            }
        }

        /// The still frame: as the ring first appears, preparing's light a little past the top,
        /// where the study draws it.
        var frame: StatusRingFrame {
            let events = StatusRingEvents(appearing: phase, fraction: eighths.map { Double($0) / 8 })
            return StatusRing.frame(at: phase == .preparing ? 0.95 : 0, events: events, reduceMotion: false)
        }
    }

    // The cycle states draw River's mark, the model's states its status ring; a cycle error
    // keeps its SF Symbol.
    enum Icon: Equatable {
        case glyph(Glyph)
        case ring(Ring)
        case symbol(String)
    }

    struct Visual: Equatable {
        let icon: Icon
        let statusLabel: String
        /// The ring beside the status line in the menu, for the model's states.
        var statusRing: Ring? = nil
    }

    // core-feature.md item 5: Ready (.idle) shows 川; Listening (.recording) adds the red dot;
    // Transcribing (.processing) the muted dot; labels "Ready" / "Recording..." / "Processing...".
    // A pending error overrides the *idle* icon with a warning glyph — errors
    // surface at end-of-cycle, so an active state's icon always wins.
    //
    // While the model downloads, gets ready, or couldn't load (planning 0004), idle shows its
    // status ring and says so instead of "Ready", which would be a lie. Active cycle states
    // (.recording / .processing) keep their own icon; a dictation waiting for the model says in
    // the status line what it waits for, in place of "Processing...". `fraction` is the model
    // in use's download.
    static func visual(state: RiverState, hasError: Bool, modelLoadState: ModelLoadState = .ready,
                       fraction: Double? = nil) -> Visual {
        let ring = Ring.of(modelLoadState, fraction: fraction)
        let words = ring.map { statusLabel($0, fraction: fraction) }
        switch state {
        case .recording:
            return Visual(icon: .glyph(.listening), statusLabel: "Recording...")
        case .processing:
            return Visual(icon: .glyph(.transcribing), statusLabel: words ?? "Processing...", statusRing: ring)
        case .idle:
            if let ring, let words { return Visual(icon: .ring(ring), statusLabel: words, statusRing: ring) }
            let icon: Icon = hasError ? .symbol("exclamationmark.triangle") : .glyph(.ready)
            return Visual(icon: icon, statusLabel: "Ready")
        }
    }

    // The menu's words for the model's state, as the preparing status study writes them.
    private static func statusLabel(_ ring: Ring, fraction: Double?) -> String {
        switch ring.phase {
        case .downloading: "Downloading model… \(Int(((fraction ?? 0) * 100).rounded(.down)))%"
        case .preparing: "Getting the model ready…"
        case .failed: "Couldn’t load the model"
        case .ready: "Ready"
        }
    }
}
