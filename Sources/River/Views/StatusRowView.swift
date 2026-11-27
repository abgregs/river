import AppKit
import SwiftUI

/// What the status says (planning 0004, 0018): why the text hasn't typed yet, or what went
/// wrong, in full, and what VoiceOver hears, which names each change of status but never a
/// percentage.
struct StatusRowWords: Equatable {
    let main: String
    let detail: String?
    let spoken: String

    /// The words for `status`, the ring at `frame` (whose arc gives the percentage, so it counts
    /// with the arc), and the Paste last shortcut's display and spoken text, nil when it doesn't
    /// work. A failure keeps the words it had until the ring has half turned akane.
    static func of(_ status: DictationStatus, frame: StatusRingFrame?,
                   pasteLast: (display: String, spoken: String)?) -> StatusRowWords {
        let arc = frame?.layers.flatMap(\.marks).lazy.compactMap { if case .arc(let fraction, _) = $0 { fraction } else { nil } }.first
        let downloading = StatusRowWords(main: "Typing after model download", detail: "\(Int(((arc ?? 0) * 100).rounded(.down)))%",
                                         spoken: "Typing after model download")
        let preparing = StatusRowWords(main: "Typing once model is ready", detail: nil, spoken: "Typing once model is ready")
        switch status {
        case .model(.downloading):
            return downloading
        case .model(.preparing):
            return preparing
        case .model(.ready):
            return StatusRowWords(main: "Ready", detail: nil, spoken: "Ready")
        case .model(.failed):
            if let frame, frame.akane < 0.5 { return arc == nil ? preparing : downloading }
            return StatusRowWords(main: "Couldn’t load the model", detail: "Recording kept",
                                  spoken: "Couldn’t load the model. Recording kept.")
        case .held:
            // One title for every dictation River couldn't type, then how to get its text.
            guard let pasteLast else {
                return StatusRowWords(main: "Couldn’t paste", detail: "Copy it from the menu", spoken: "Couldn’t paste. Copy it from the menu.")
            }
            return StatusRowWords(main: "Couldn’t paste", detail: "\(pasteLast.display) pastes it",
                                  spoken: "Couldn’t paste. \(pasteLast.spoken) pastes it.")
        case .error(let error):
            return StatusRowWords(main: error.headline, detail: error.detail, spoken: "\(error.headline). \(error.detail).")
        }
    }

    /// Every row River can write with this shortcut, for the test that the window is wide enough.
    static func all(pasteLast: (display: String, spoken: String)) -> [StatusRowWords] {
        struct Failure: Error {}
        let failed = StatusRingFrame(layers: [], akane: 1)
        let full = StatusRingFrame(layers: [.init(opacity: 1, marks: StatusRing.download(1, breath: 0))], akane: 0)
        let errors: [RiverError] = [
            .audioCapture(underlying: Failure()),
            .audioCapture(underlying: AudioCaptureError.captureIncomplete(capturedSeconds: 1, recordingSeconds: 2)),
            .transcription(underlying: Failure()), .textInsertion(underlying: Failure()),
        ] + ["Microphone", "Accessibility", "Input Monitoring"].map { .permission(capability: $0) }
        return [of(.model(.downloading), frame: full, pasteLast: pasteLast), of(.model(.preparing), frame: nil, pasteLast: pasteLast),
                of(.model(.ready), frame: nil, pasteLast: pasteLast), of(.model(.failed), frame: failed, pasteLast: pasteLast),
                of(.held, frame: nil, pasteLast: pasteLast), of(.held, frame: nil, pasteLast: nil)]
            + errors.map { of(ErrorStatusPresentation.status(for: $0), frame: nil, pasteLast: pasteLast) }
    }
}

/// The status in the mark's place (planning 0004, 0018): the ring or the lock in its tile,
/// then the words, always in full. The stack brings it in once the mark's panel has
/// gone and takes it out on the HUD's fade; a model's status follows the model through preparing
/// to ready in place. It never takes the mouse: the window ignores it, as it does the panel.
struct StatusRow: View {
    let status: DictationStatus
    let appState: AppState
    @State private var ring: StatusRingCycle?
    @AppStorage(Settings.pasteLastShortcut.name)
    private var pasteLastShortcut: Shortcut = Settings.pasteLastShortcut.defaultValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // `ring` is internal for testability: the snapshot harness hands in a ring already under way.
    init(status: DictationStatus, appState: AppState, ring: StatusRingCycle? = nil) {
        self.status = status
        self.appState = appState
        _ring = State(initialValue: ring)
    }

    /// An error's mark, and held text's: Couldn't load the model's ring, already failed, as a
    /// ring that appears failed shows it, all at once.
    static let failedRing = StatusRing.frame(at: 0, events: StatusRingEvents(appearing: .failed, fraction: nil), reduceMotion: false)

    var body: some View {
        // Only the model's ring moves; an error or held text is one still frame.
        TimelineView(.animation(paused: !isRing)) { context in
            let frame = isRing ? ring.map { StatusRing.frame(at: $0.time(at: context.date), events: $0.events, reduceMotion: reduceMotion) } : nil
            let words = StatusRowWords.of(status, frame: frame, pasteLast: pasteLast)
            StatusRowFace(words: words, glyph: Self.glyph(for: status, frame: frame))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(words.spoken)
        }
        .onChange(of: status, initial: true) {
            updateRing()
            announce()
        }
        .onChange(of: appState.downloadFraction) { updateRing() }
    }

    // internal for testability — the tile's glyph for a status. Text River couldn't type takes
    // the failure's mark: something went wrong, and the user has to act (maintainer, 2026-11-27).
    static func glyph(for status: DictationStatus, frame: StatusRingFrame?) -> StatusGlyph {
        switch status {
        case .model: .ring(frame ?? StatusRingFrame(layers: [], akane: 0))
        case .held: .ring(failedRing)
        case .error(let error): error.mark == .locked ? .locked : .ring(failedRing)
        }
    }

    private var isRing: Bool {
        if case .model = status { true } else { false }
    }

    // The shortcut's text, or nil when it failed to register, so the words send the user to the
    // menu instead.
    private var pasteLast: (display: String, spoken: String)? {
        if let registration = appState.shortcutRegistrations[.pasteLast], registration != .registered { return nil }
        return (ShortcutText.display(pasteLastShortcut), ShortcutText.spoken(pasteLastShortcut))
    }

    private func updateRing() {
        guard case .model(let phase) = status else { return }
        ring = StatusRingCycle.next(ring, phase: phase, model: appState.modelSelection.inUse,
                                    fraction: appState.downloadFraction, at: Date())
    }

    // Each change of status, never each percent, at high priority: River is in the background
    // while the user waits in another app.
    private func announce() {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        let words = StatusRowWords.of(status, frame: nil, pasteLast: pasteLast)
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [.announcement: words.spoken, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

/// What the row's tile shows: the status ring, or a permission error's lock.
enum StatusGlyph: Equatable {
    case ring(StatusRingFrame)
    case locked
}

/// The row at one moment: the glyph in its 26 pt tile, padded inside the floating UI's surface
/// with the window's edge, then the words.
struct StatusRowFace: View {
    let words: StatusRowWords
    let glyph: StatusGlyph
    @Environment(\.colorScheme) private var colorScheme

    private typealias C = Constants

    var body: some View {
        let ink = Palette.HUD.for(colorScheme).text
        HStack(spacing: 0) {
            Group {
                switch glyph {
                case .ring(let frame):
                    StatusRingGlyph(frame: frame)
                case .locked:
                    Canvas { context, size in LockRenderer.draw(in: &context, size: size, ink: ink) }
                }
            }
            .frame(width: StatusRing.grid, height: StatusRing.grid)
            .padding(C.statusRowGlyphInset)
            .overlay {
                RoundedRectangle(cornerRadius: C.statusRowTileRadius, style: .continuous)
                    .inset(by: 0.25)
                    .stroke(Color(nsColor: ink).opacity(C.statusRowHairlineOpacity), lineWidth: 0.5)
            }
            Text(words.main)
                .padding(.leading, C.statusRowTextGap)
            if let detail = words.detail {
                detailText(detail)
                    .foregroundStyle(Color(nsColor: ink).opacity(C.hudSecondaryTextOpacity))
                    .padding(.leading, C.statusRowDetailGap)
            }
        }
        .font(.system(size: C.statusRowFontSize))
        .foregroundStyle(Color(nsColor: ink))
        .lineLimit(1)
        .padding(.vertical, C.statusRowPadding)
        .padding(.leading, C.statusRowPadding)
        .padding(.trailing, C.statusRowTrailingPadding)
        .frame(height: C.statusRowHeight)
        .fixedSize()
        .modifier(HUDSurface(cornerRadius: C.statusRowCornerRadius, edge: .window))
    }

    // A percentage keeps the width of "100%", so the row holds still while the number climbs.
    @ViewBuilder private func detailText(_ detail: String) -> some View {
        if detail.hasSuffix("%") {
            Text("100%").monospacedDigit().hidden().overlay(alignment: .leading) { Text(detail).monospacedDigit() }
        } else {
            Text(detail)
        }
    }
}

/// A permission error's glyph, on the 14 pt grid: the shackle in outline, the body solid with
/// its keyhole cut out, so the tile shows through it.
enum LockRenderer {
    static func draw(in context: inout GraphicsContext, size: CGSize, ink: NSColor) {
        var c = context
        c.scaleBy(x: size.width / StatusRing.grid, y: size.height / StatusRing.grid)
        func color(_ alpha: Double) -> GraphicsContext.Shading { .color(Color(nsColor: ink).opacity(alpha)) }
        var shackle = Path()
        shackle.move(to: CGPoint(x: 4.75, y: 6.6))
        shackle.addLine(to: CGPoint(x: 4.75, y: 4.6))
        shackle.addArc(center: CGPoint(x: 7, y: 4.6), radius: 2.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        shackle.addLine(to: CGPoint(x: 9.25, y: 6.6))
        c.stroke(shackle, with: color(0.45), style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round))
        c.drawLayer { layer in
            layer.fill(RoundedRectangle(cornerRadius: 1.6, style: .continuous).path(in: CGRect(x: 3.1, y: 6.3, width: 7.8, height: 6)),
                       with: color(0.9))
            layer.blendMode = .destinationOut
            layer.fill(Path(ellipseIn: CGRect(x: 6.05, y: 7.9, width: 1.9, height: 1.9)), with: .color(.black))
            var stem = Path()
            stem.move(to: CGPoint(x: 7, y: 8.85))
            stem.addLine(to: CGPoint(x: 7, y: 10.6))
            layer.stroke(stem, with: .color(.black), style: StrokeStyle(lineWidth: 0.95, lineCap: .round))
        }
    }
}
