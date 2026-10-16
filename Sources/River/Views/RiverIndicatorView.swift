import AppKit
import SwiftUI

/// Everything River floats above the Dock, as one bottom-anchored stack (planning 0028; the
/// mark is the stones of docs/design/stones-identity.md): the mark's panel, which carries only
/// the recording state;
/// above it one rounded rectangle for the error toast (0018), the model-loading label
/// (0004), and the live-reconfiguration notice; and above that the streaming transcript
/// (0025). It observes `AppState` only; every number that shapes the motion lives in the
/// pure `StoneMarkPresentation`, and panel and focus behavior live in the coordinator.
struct RiverIndicatorView: View {
    let appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// The stack at its tallest: transcript, message, and mark. The window is this plus the
    /// shadow margin and never resizes, so nothing on screen moves under a transition.
    static let contentSize = CGSize(
        width: max(Constants.transcriptPanelWidth, Constants.hudMessageWidth),
        height: Constants.transcriptPanelHeight + Constants.hudStackSpacing
            + Constants.hudMessageReservedHeight + Constants.hudStackSpacing + Constants.indicatorPanelHeight
    )

    var body: some View {
        // Each surface takes space only while it shows, so the ones above close the gap: a
        // toast left after the cycle drops to where the mark was, and a message never lands on
        // the transcript. The bottom of the stack sits just above the Dock.
        VStack(spacing: Constants.hudStackSpacing) {
            if isTranscriptShown {
                TranscriptPanelView(text: appState.liveTranscript)
                    .transition(fade)
            }
            if hasMessage {
                messages
                    .transition(fade)
            }
            if isMarkShown {
                MarkPanel(activity: activity, inputLevel: Double(appState.inputLevel))
                    .transition(fade)
            }
        }
        .frame(width: Self.contentSize.width, height: Self.contentSize.height, alignment: .bottom)
        .padding(Constants.hudShadowMargin)
        .animation(.easeOut(duration: Constants.hudFadeSeconds), value: appState.state)
        .animation(.easeOut(duration: Constants.hudFadeSeconds), value: appState.toast)
        .animation(.easeOut(duration: Constants.hudFadeSeconds), value: appState.modelLoadState)
        .animation(.easeOut(duration: Constants.hudFadeSeconds), value: appState.notice)
        .animation(.easeOut(duration: Constants.hudFadeSeconds), value: isTranscriptShown)
    }

    // Enter and exit: opacity with a 6 pt rise, ease-out both ways; a plain fade under Reduce Motion.
    private var fade: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: Constants.hudFadeRise))
    }

    private var isTranscriptShown: Bool {
        TranscriptPanelView.isVisible(state: appState.state, text: appState.liveTranscript)
    }

    // Loading only matters while idle: the model is ready before recording is permitted.
    private var loadingLabel: String? {
        appState.state == .idle ? RecordingIndicatorPresentation.loadingLabel(for: appState.modelLoadState) : nil
    }

    // While the model gets ready the mark holds the r, not a spinner.
    private var activity: MarkActivity {
        MarkActivity.of(state: appState.state, isModelPreparing: loadingLabel != nil)
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
        .foregroundStyle(Color(nsColor: Palette.HUD.for(colorScheme).text))
        .background { HUDSurface(cornerRadius: Constants.hudMessageCornerRadius) }
        .accessibilityElement(children: .combine)
    }
}

/// The panel around the mark, and the mark's accessible name: the stones are decorative,
/// so the panel speaks the state and, while listening, the elapsed time. While preparing,
/// the label above speaks instead.
private struct MarkPanel: View {
    let activity: MarkActivity
    let inputLevel: Double
    @State private var recordingStart = Date()

    var body: some View {
        TimelineView(.animation(paused: activity == .rest)) { context in
            StoneMarkView(activity: activity, inputLevel: inputLevel, date: context.date)
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

/// The stones mark, drawn per display frame from the pure presentation functions.
private struct StoneMarkView: View {
    let activity: MarkActivity
    let inputLevel: Double
    let date: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var engine = StoneMarkEngine()

    var body: some View {
        Canvas { context, size in
            let now = date.timeIntervalSinceReferenceDate
            let frame = engine.frame.advanced(to: now, activity: activity, inputLevel: inputLevel, reduceMotion: reduceMotion)
            engine.frame = frame
            StoneMarkRenderer.draw(frame, in: &context, size: size, colors: .for(colorScheme))
        }
        .frame(width: Constants.indicatorMarkSize, height: Constants.indicatorMarkSize)
        .accessibilityHidden(true)
        // A new cycle starts from the r at rest, not from wherever the last one was left
        // when the timeline paused at idle.
        .onChange(of: activity) { oldActivity, _ in
            if oldActivity == .rest { engine.frame = StoneMarkFrame() }
        }
    }
}

/// Draws the three stones for one frame. Shared by the live mark and the snapshot harness,
/// so a held frame is the shipped drawing, not a copy of it.
enum StoneMarkRenderer {
    // The accent means River is on, so while it records or transcribes the mark takes the
    // panel's accent. Preparing the model is not a dictation: the r waits in the text color.
    static func draw(_ frame: StoneMarkFrame, in context: inout GraphicsContext, size: CGSize, colors: Palette.HUD) {
        context.opacity = frame.opacity
        let color = Color(nsColor: frame.activity == .preparing ? colors.text : colors.accent)
        let height = Constants.indicatorMarkHeight
        let transform = CGAffineTransform(translationX: frame.centering, y: 0).concatenating(
            StoneMark.transform(fitting: StoneMark.bounds,
                                into: CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)))
        for index in StoneMark.pieces.indices {
            context.fill(Path(StoneMark.path(frame.outline(ofPiece: index), transform: transform)), with: .color(color))
        }
    }
}

/// Holds the engine's frame between renders. A reference so the renderer can advance it
/// without invalidating the view; nothing observes it.
private final class StoneMarkEngine {
    var frame = StoneMarkFrame()
}

/// The surface every floating shape shares (the mark's panel, the message rectangle, the
/// transcript panel), built like a native HUD window in the system's appearance: the desktop
/// behind it blurred under a tint (charcoal in Dark mode, mist in Light), a white inner
/// hairline that brightens along the top edge where light would catch it, a dark outer line
/// that keeps the edge crisp, and one soft shadow. Under Reduce Transparency, an opaque fill
/// of the tint replaces the blur and the tint.
struct HUDSurface: View {
    let cornerRadius: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let colors = Palette.HUD.for(colorScheme)
        ZStack {
            if reduceTransparency {
                shape.fill(Color(nsColor: colors.tint))
            } else {
                BackdropBlur(cornerRadius: cornerRadius, dark: colorScheme == .dark)
                shape.fill(Color(nsColor: colors.tint).opacity(colors.tintOpacity))
            }
        }
        .overlay { shape.strokeBorder(Self.hairline(colors), lineWidth: Constants.hudHairlineWidth) }
        .overlay {
            shape.inset(by: -Constants.hudOuterLineWidth)
                .strokeBorder(.black.opacity(colors.outerLineOpacity), lineWidth: Constants.hudOuterLineWidth)
        }
        .background { Self.shadow(shape) }
    }

    private static func hairline(_ colors: Palette.HUD) -> LinearGradient {
        LinearGradient(
            stops: [.init(color: .white.opacity(colors.hairlineTopOpacity), location: 0),
                    .init(color: .white.opacity(colors.hairlineOpacity), location: 0.15)],
            startPoint: .top, endPoint: .bottom)
    }

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
/// the view is forced active (an inactive one draws flat gray). Its appearance is set from the
/// same color scheme as the tint, so blur and tint always flip together. A behind-window blur
/// ignores layer masks; only `maskImage` shapes it, drawn here with the same continuous corner
/// as the tint.
private struct BackdropBlur: NSViewRepresentable {
    let cornerRadius: Double
    let dark: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.mask(cornerRadius: cornerRadius)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }

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
