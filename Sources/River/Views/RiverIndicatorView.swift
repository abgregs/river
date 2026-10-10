import AppKit
import SwiftUI

/// The recording indicator's SwiftUI content (planning 0028, mark replaced in 0029): the
/// pixel mark's panel, which carries only the recording state, and below it one rounded
/// rectangle for the error toast (0018), the model-loading label (0004), and the
/// live-reconfiguration notice. It observes `AppState` only; every number that shapes the
/// motion lives in the pure `PixelMarkPresentation`, and panel and focus behavior live in
/// the coordinator.
struct RiverIndicatorView: View {
    let appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Fixed geometry: the mark's panel keeps its place whether or not a message is on
        // screen, and the window never resizes under an animating transition. The mark sits
        // just above the Dock. A message sits above the mark while the mark shows, and on the
        // mark's own baseline once it has gone, so a toast left after the cycle never floats
        // over an empty gap.
        ZStack(alignment: .bottom) {
            MarkPanel(activity: activity, inputLevel: Double(appState.inputLevel))
                .modifier(HUDFade(isVisible: isMarkShown, reduceMotion: reduceMotion))
            if hasMessage {
                messages
                    .offset(y: isMarkShown ? -(Constants.indicatorPanelHeight + Constants.hudStackSpacing) : 0)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: Constants.hudFadeRise)))
            }
        }
        .frame(width: Constants.hudMessageWidth,
               height: Constants.hudMessageReservedHeight + Constants.hudStackSpacing + Constants.indicatorPanelHeight,
               alignment: .bottom)
        .padding(Constants.hudShadowMargin)
        .animation(.easeOut(duration: Constants.hudFadeSeconds), value: appState.state)
        .animation(.easeOut(duration: Constants.hudFadeSeconds), value: appState.toast)
        .animation(.easeOut(duration: Constants.hudFadeSeconds), value: appState.modelLoadState)
        .animation(.easeOut(duration: Constants.hudFadeSeconds), value: appState.notice)
    }

    // Loading only matters while idle: the model is ready before recording is permitted.
    private var loadingLabel: String? {
        appState.state == .idle ? RecordingIndicatorPresentation.loadingLabel(for: appState.modelLoadState) : nil
    }

    // While the model gets ready the mark shows the waiting crest, not a spinner.
    private var activity: PixelMarkActivity {
        PixelMarkActivity.of(state: appState.state, isModelPreparing: loadingLabel != nil)
    }

    // A notice belongs to the recording it describes: showing one at `.idle` would put
    // last cycle's message under a capsule that is on its way out (planning 0017's
    // canceled-notice bleed). The menu row stays its lingering home.
    private var notice: String? {
        appState.state == .recording ? appState.notice : nil
    }

    private var isMarkShown: Bool { activity != .rest }

    private var hasMessage: Bool {
        appState.toast != nil || loadingLabel != nil || notice != nil
    }

    private var isPreparingLabelOnly: Bool {
        loadingLabel != nil && appState.toast == nil && notice == nil
    }

    private var messages: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let toast = appState.toast {
                ToastRow(toast: toast)
            }
            if let label = loadingLabel {
                Text(label).font(.callout)
            }
            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Constants.hudMessagePadding)
        // The preparing label alone hugs its text and centers under the mark; toasts and
        // notices keep the full width their wrapped prose needs.
        .frame(width: isPreparingLabelOnly ? nil : Constants.hudMessageWidth, alignment: .leading)
        .foregroundStyle(Color(nsColor: Palette.ink))
        .background { HUDSurface(cornerRadius: Constants.hudMessageCornerRadius) }
        // The surface is charcoal on every desktop, so its text takes the dark appearance's
        // colors regardless of the system's.
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }
}

/// The panel around the mark, and the mark's accessible name: the pixels are decorative,
/// so the panel speaks the state and, while listening, the elapsed time. While preparing,
/// the label below speaks instead.
private struct MarkPanel: View {
    let activity: PixelMarkActivity
    let inputLevel: Double
    @State private var recordingStart = Date()

    var body: some View {
        TimelineView(.animation(paused: activity == .rest)) { context in
            PixelMarkView(activity: activity, inputLevel: inputLevel, date: context.date)
                .padding(.horizontal, Constants.indicatorPanelHorizontalPadding)
                .padding(.vertical, Constants.indicatorPanelVerticalPadding)
                .background { HUDSurface(cornerRadius: Constants.indicatorPanelCornerRadius) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(activity == .transcribing ? "Transcribing" : "Listening")
                .accessibilityValue(activity == .listening ? elapsed(at: context.date) : "")
                .accessibilityHidden(activity == .rest || activity == .preparing)
        }
        .onChange(of: activity) { _, newActivity in
            if newActivity == .listening { recordingStart = Date() }
        }
    }

    private func elapsed(at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(recordingStart)))
        return Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }
}

/// The pixel mark, drawn per display frame from the pure presentation functions.
private struct PixelMarkView: View {
    let activity: PixelMarkActivity
    let inputLevel: Double
    let date: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var engine = PixelMarkEngine()

    var body: some View {
        Canvas { context, _ in
            let now = date.timeIntervalSinceReferenceDate
            let frame = engine.frame.advanced(to: now, activity: activity, inputLevel: inputLevel, reduceMotion: reduceMotion)
            engine.frame = frame
            PixelMarkRenderer.draw(frame, increaseContrast: contrast == .increased, in: &context)
        }
        .frame(width: Constants.pixelMarkSize, height: Constants.pixelMarkSize)
        .accessibilityHidden(true)
        // A new cycle starts from the r at rest, not from wherever the last one was left
        // when the timeline paused at idle.
        .onChange(of: activity) { oldActivity, _ in
            if oldActivity == .rest { engine.frame = PixelMarkFrame() }
        }
    }
}

/// Draws the sixteen pixels for one frame. Shared by the live mark and the snapshot
/// harness, so a held frame is the shipped drawing, not a copy of it.
enum PixelMarkRenderer {
    static func draw(_ frame: PixelMarkFrame, increaseContrast: Bool, in context: inout GraphicsContext) {
        context.opacity = frame.opacity
        let radius = PixelMark.cornerRadius(cell: Constants.pixelCell)
        for (index, cell) in PixelMark.cells.enumerated() {
            let offset = frame.offset(ofCell: index)
            let rect = PixelMark.cellRect(x: Double(cell.x) + offset.x, y: Double(cell.y) + offset.y,
                                          cell: Constants.pixelCell, gap: Constants.pixelGap)
            let ink = PixelMarkPresentation.displayInk(frame.ink[index], increaseContrast: increaseContrast)
            context.fill(Path(roundedRect: rect, cornerRadius: radius),
                         with: .color(color(accentMix: frame.accentMix[index]).opacity(ink)))
        }
    }

    // The panel is charcoal on every desktop, so the lit meter takes the dark accent.
    private static let inkComponents = components(Palette.ink)
    private static let accentComponents = components(Palette.accentDark)

    static func color(accentMix: Double) -> Color {
        let ink = inkComponents, accent = accentComponents
        let mix = min(1, max(0, accentMix))
        return Color(.sRGB,
                     red: ink.red + (accent.red - ink.red) * mix,
                     green: ink.green + (accent.green - ink.green) * mix,
                     blue: ink.blue + (accent.blue - ink.blue) * mix)
    }

    private static func components(_ color: NSColor) -> (red: Double, green: Double, blue: Double) {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        return (srgb.redComponent, srgb.greenComponent, srgb.blueComponent)
    }
}

/// Holds the engine's frame between renders. A reference so the renderer can advance it
/// without invalidating the view; nothing observes it.
private final class PixelMarkEngine {
    var frame = PixelMarkFrame()
}

/// The surface every floating shape shares (the mark's panel, the message rectangle, the
/// transcript panel), built like a native dark HUD window: the desktop behind it blurred
/// dark under a charcoal tint, a light inner hairline that brightens along the top edge
/// where light would catch it, a dark outer line that keeps the edge crisp over light
/// desktops, and one soft shadow. Under Reduce Transparency, a near-opaque fill replaces
/// the blur and the tint.
struct HUDSurface: View {
    let cornerRadius: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if reduceTransparency {
                shape.fill(Color(nsColor: Palette.charcoal).opacity(Constants.hudSolidFillOpacity))
            } else {
                BackdropBlur(cornerRadius: cornerRadius)
                shape.fill(Color(nsColor: Palette.deepCharcoal).opacity(Constants.hudTintOpacity))
            }
        }
        .overlay { shape.strokeBorder(Self.hairline, lineWidth: Constants.hudHairlineWidth) }
        .overlay {
            shape.inset(by: -Constants.hudOuterLineWidth)
                .strokeBorder(.black.opacity(Constants.hudOuterLineOpacity), lineWidth: Constants.hudOuterLineWidth)
        }
        .background { Self.shadow(shape) }
    }

    private static let hairline = LinearGradient(
        stops: [.init(color: .white.opacity(Constants.hudHairlineTopOpacity), location: 0),
                .init(color: .white.opacity(Constants.hudHairlineOpacity), location: 0.15)],
        startPoint: .top, endPoint: .bottom)

    // The shadow with the shape cut out of it, so it only ever shows outside the edge and
    // never darkens the blur or the tint.
    private static func shadow(_ shape: RoundedRectangle) -> some View {
        shape.fill(.black)
            .shadow(color: .black.opacity(Constants.hudShadowOpacity), radius: Constants.hudShadowRadius, y: Constants.hudShadowOffset)
            .mask {
                Rectangle()
                    .padding(-Constants.hudShadowMargin)
                    .overlay { shape.blendMode(.destinationOut) }
                    .compositingGroup()
            }
    }
}

/// A window-server blur of whatever is behind the panel. River is never the active app, so
/// the view is forced active (an inactive one draws flat gray), and forced dark so the blur
/// matches the charcoal palette on every desktop. A behind-window blur ignores layer masks;
/// only `maskImage` shapes it, drawn here with the same continuous corner as the tint.
private struct BackdropBlur: NSViewRepresentable {
    let cornerRadius: Double

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.maskImage = Self.mask(cornerRadius: cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}

    // A stretchable image of the corner: a continuous corner starts curving about 1.53 radii
    // from the corner, so the cap insets hold the whole curve.
    static func mask(cornerRadius: Double) -> NSImage {
        let cap = (cornerRadius * 1.6).rounded(.up)
        let side = 2 * cap + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let path = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(path.cgPath)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cap, left: cap, bottom: cap, right: cap)
        image.resizingMode = .stretch
        return image
    }
}

/// Enter and exit: opacity with a 6 pt rise, ease-out both ways; a plain fade under Reduce Motion.
private struct HUDFade: ViewModifier {
    let isVisible: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : Constants.hudFadeRise)
    }
}

/// The transient error toast: headline and recovery hint (planning 0018), as plain prose.
/// Warning graphics are deliberately left for a later pass (maintainer, 2026-09-17).
private struct ToastRow: View {
    let toast: ErrorToast

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(toast.headline).font(.callout.weight(.semibold))
            Text(toast.hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
