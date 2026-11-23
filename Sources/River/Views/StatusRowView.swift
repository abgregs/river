import AppKit
import SwiftUI

/// What the status row says (planning 0004):
/// why the text hasn't typed yet, in full, and what VoiceOver hears, which names each
/// change of status but never a percentage.
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
            guard let pasteLast else {
                return StatusRowWords(main: "App switched", detail: "Copy it from the menu", spoken: "App switched. Copy it from the menu.")
            }
            return StatusRowWords(main: "App switched", detail: "\(pasteLast.display) pastes it",
                                  spoken: "App switched. \(pasteLast.spoken) pastes it.")
        }
    }

    /// Every row River can write with this shortcut, for the test that the window is wide enough.
    static func all(pasteLast: (display: String, spoken: String)) -> [StatusRowWords] {
        let failed = StatusRingFrame(layers: [], akane: 1)
        let full = StatusRingFrame(layers: [.init(opacity: 1, marks: StatusRing.download(1, breath: 0))], akane: 0)
        return [of(.model(.downloading), frame: full, pasteLast: pasteLast), of(.model(.preparing), frame: nil, pasteLast: pasteLast),
                of(.model(.ready), frame: nil, pasteLast: pasteLast), of(.model(.failed), frame: failed, pasteLast: pasteLast),
                of(.held, frame: nil, pasteLast: pasteLast), of(.held, frame: nil, pasteLast: nil)]
    }
}

/// The row's entry: the HUD's fade, 0.22 s on `easeOut` rising 6 pt, or a plain 0.2 s fade under
/// Reduce Motion. It leaves with the mark's panel.
enum StatusRowEntry {
    static func at(_ t: Double, reduceMotion: Bool) -> (opacity: Double, rise: Double) {
        if reduceMotion { return (min(1, max(0, t / Constants.kawaReducedFadeSeconds)), 0) }
        let p = CubicBezier.easeOut(min(1, max(0, t / Constants.hudFadeSeconds)))
        return (p, Constants.hudFadeRise * (1 - p))
    }
}

/// The status shown beside the mark and when it appeared, kept by the stack until the mark's
/// cycle ends.
struct ShownStatus: Equatable {
    var status: DictationStatus
    let appeared: Date
}

/// The row beside the mark (planning 0004): the ring or the held
/// sheet in its tile, then the words, always in full. It enters on the HUD's fade, follows the
/// model through preparing to ready, and leaves with the mark's panel, on the mark's own clock.
/// It never takes the mouse: the window ignores it, as it does the panel.
struct StatusRow: View {
    let shown: ShownStatus
    let markCycle: KawaIndicatorCycle
    let appState: AppState
    @State private var ring: StatusRingCycle?
    @AppStorage(Settings.pasteLastShortcut.name)
    private var pasteLastShortcut: Shortcut = Settings.pasteLastShortcut.defaultValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // `ring` is internal for testability: the snapshot harness hands in a ring already under way.
    init(shown: ShownStatus, markCycle: KawaIndicatorCycle, appState: AppState, ring: StatusRingCycle? = nil) {
        self.shown = shown
        self.markCycle = markCycle
        self.appState = appState
        _ring = State(initialValue: ring)
    }

    var body: some View {
        TimelineView(.animation) { context in
            let panel = KawaIndicatorTimeline.channels(at: markCycle.time(at: context.date), events: markCycle.events,
                                                       reduceMotion: reduceMotion)
            let entry = StatusRowEntry.at(context.date.timeIntervalSince(shown.appeared), reduceMotion: reduceMotion)
            let frame = isRing ? ring.map { StatusRing.frame(at: $0.time(at: context.date), events: $0.events, reduceMotion: reduceMotion) } : nil
            let words = StatusRowWords.of(shown.status, frame: frame, pasteLast: pasteLast)
            StatusRowFace(words: words, frame: frame)
                .opacity(entry.opacity * panel.panel)
                .offset(y: entry.rise + panel.rise)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(words.spoken)
        }
        .onChange(of: shown.status, initial: true) {
            updateRing()
            announce()
        }
        .onChange(of: appState.downloadFraction) { updateRing() }
    }

    private var isRing: Bool {
        if case .model = shown.status { true } else { false }
    }

    // The shortcut's text, or nil when it failed to register, so the words send the user to the
    // menu instead.
    private var pasteLast: (display: String, spoken: String)? {
        if let registration = appState.shortcutRegistrations[.pasteLast], registration != .registered { return nil }
        return (ShortcutText.display(pasteLastShortcut), ShortcutText.spoken(pasteLastShortcut))
    }

    private func updateRing() {
        guard case .model(let phase) = shown.status else { return }
        ring = StatusRingCycle.next(ring, phase: phase, model: appState.modelSelection.inUse,
                                    fraction: appState.downloadFraction, at: Date())
    }

    // Each change of status, never each percent, at high priority: River is in the background
    // while the user waits in another app.
    private func announce() {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        let words = StatusRowWords.of(shown.status, frame: nil, pasteLast: pasteLast)
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [.announcement: words.spoken, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

/// The row at one moment: the glyph in its 26 pt tile, then the words, on the floating UI's
/// surface with the window's edge.
struct StatusRowFace: View {
    let words: StatusRowWords
    /// The ring's frame, or nil for the held sheet.
    let frame: StatusRingFrame?
    @Environment(\.colorScheme) private var colorScheme

    private typealias C = Constants

    var body: some View {
        let ink = Color(nsColor: Palette.HUD.for(colorScheme).text)
        HStack(spacing: 0) {
            Group {
                if let frame {
                    StatusRingGlyph(frame: frame)
                } else {
                    Canvas { context, size in
                        HeldSheetRenderer.draw(in: &context, size: size, ink: Palette.HUD.for(colorScheme).text)
                    }
                    .frame(width: StatusRing.grid, height: StatusRing.grid)
                }
            }
            .padding(C.statusRowGlyphInset)
            .overlay {
                RoundedRectangle(cornerRadius: C.statusRowCornerRadius, style: .continuous)
                    .inset(by: C.statusRowHairlineInset)
                    .stroke(ink.opacity(C.statusRowHairlineOpacity), lineWidth: 0.5)
            }
            Text(words.main)
                .padding(.leading, C.statusRowTextInset - C.statusRowHeight)
            if let detail = words.detail {
                detailText(detail)
                    .foregroundStyle(ink.opacity(C.hudSecondaryTextOpacity))
                    .padding(.leading, C.statusRowDetailGap)
            }
        }
        .font(.system(size: C.statusRowFontSize))
        .foregroundStyle(ink)
        .lineLimit(1)
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

/// App changed's glyph: a finished sheet under a paperweight, on the 14 pt grid.
enum HeldSheetRenderer {
    static func draw(in context: inout GraphicsContext, size: CGSize, ink: NSColor) {
        var c = context
        c.scaleBy(x: size.width / StatusRing.grid, y: size.height / StatusRing.grid)
        c.translateBy(x: 7, y: 7.6)
        c.rotate(by: .degrees(-6))
        c.translateBy(x: -7, y: -7.6)
        func color(_ alpha: Double) -> GraphicsContext.Shading { .color(Color(nsColor: ink).opacity(alpha)) }
        let sheet = RoundedRectangle(cornerRadius: 1, style: .continuous).path(in: CGRect(x: 3.1, y: 3, width: 7.8, height: 10))
        c.fill(sheet, with: color(0.12))
        c.stroke(sheet, with: color(0.45), style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round))
        var lines = Path()
        for (y, end) in [(6.6, 9.2), (8.6, 9.2), (10.6, 7.6)] {
            lines.move(to: CGPoint(x: 4.9, y: y))
            lines.addLine(to: CGPoint(x: end, y: y))
        }
        c.stroke(lines, with: color(0.45), style: StrokeStyle(lineWidth: 1.05, lineCap: .round, lineJoin: .round))
        let weight = RoundedRectangle(cornerRadius: 0.7, style: .continuous).path(in: CGRect(x: 4.7, y: 1.9, width: 4.6, height: 2.3))
        c.fill(weight, with: color(0.9))
    }
}
