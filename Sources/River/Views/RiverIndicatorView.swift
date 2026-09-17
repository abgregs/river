import SwiftUI

/// The recording indicator's SwiftUI content (planning 0028): the river capsule, which
/// carries only the recording state, and below it one rounded rectangle for the error
/// toast (0018), the model-loading label (0004), and the live-reconfiguration notice.
/// It observes `AppState` only; every number that shapes the motion lives in the pure
/// `RiverIndicatorPresentation`, and panel and focus behavior live in the coordinator.
struct RiverIndicatorView: View {
    let appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Constants.hudStackSpacing) {
            RiverCapsule(state: appState.state, inputLevel: Double(appState.inputLevel))
                .modifier(HUDFade(isVisible: appState.state != .idle, reduceMotion: reduceMotion))
            if hasMessage {
                messages
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: Constants.hudFadeRise)))
            }
        }
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

    private var hasMessage: Bool {
        appState.toast != nil || loadingLabel != nil || appState.notice != nil
    }

    private var messages: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let toast = appState.toast {
                ToastRow(toast: toast)
            }
            if let label = loadingLabel {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(label).font(.callout)
                }
            }
            if let notice = appState.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Constants.hudMessagePadding)
        .frame(width: Constants.hudMessageWidth, alignment: .leading)
        .foregroundStyle(Color(nsColor: Palette.ink))
        .background { HUDSurface(shape: RoundedRectangle(cornerRadius: Constants.hudMessageCornerRadius, style: .continuous)) }
        // The surface is charcoal on every desktop, so its text and spinner take the dark
        // appearance's colors regardless of the system's.
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }
}

/// The capsule around the mark, and the mark's accessible name: the strands are
/// decorative, so the capsule speaks the state and, while listening, the elapsed time.
private struct RiverCapsule: View {
    let state: RiverState
    let inputLevel: Double
    @State private var recordingStart = Date()

    var body: some View {
        TimelineView(.animation(paused: state == .idle)) { context in
            RiverMark(state: state, inputLevel: inputLevel, date: context.date)
                .padding(.horizontal, Constants.riverCapsuleHorizontalPadding)
                .padding(.vertical, Constants.riverCapsuleVerticalPadding)
                .background { HUDSurface(shape: Capsule()) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(state == .processing ? "Transcribing" : "Listening")
                .accessibilityValue(state == .recording ? elapsed(at: context.date) : "")
                .accessibilityHidden(state == .idle)
        }
        .onChange(of: state) { _, newState in
            if newState == .recording { recordingStart = Date() }
        }
    }

    private func elapsed(at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(recordingStart)))
        return Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }
}

/// The three strands, drawn per display frame from the pure presentation functions.
private struct RiverMark: View {
    let state: RiverState
    let inputLevel: Double
    let date: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var engine = RiverEngine()

    var body: some View {
        Canvas { context, _ in
            let now = date.timeIntervalSinceReferenceDate
            let frame = engine.frame.advanced(to: now, state: state, inputLevel: inputLevel, reduceMotion: reduceMotion)
            engine.frame = frame
            RiverMarkRenderer.draw(frame, time: now, reduceMotion: reduceMotion, in: &context)
        }
        .frame(width: Constants.riverMarkWidth, height: Constants.riverMarkHeight)
        .accessibilityHidden(true)
        // A new cycle starts from rest, not from wherever the last one's level was left
        // when the timeline paused at idle.
        .onChange(of: state) { oldState, _ in
            if oldState == .idle { engine.frame = RiverIndicatorFrame() }
        }
    }
}

/// Draws the three strands for one frame. Shared by the live mark and the snapshot
/// harness, so a held frame is the shipped drawing, not a copy of it.
enum RiverMarkRenderer {
    static func draw(_ frame: RiverIndicatorFrame, time: Double, reduceMotion: Bool, in context: inout GraphicsContext) {
        typealias River = RiverIndicatorPresentation
        let ink = Color(nsColor: Palette.ink)
        let width = Constants.riverMarkWidth
        let fade = Constants.riverEndFadeFraction
        context.clipToLayer { mask in
            mask.fill(Path(CGRect(x: 0, y: 0, width: width, height: Constants.riverMarkHeight)), with: .linearGradient(
                Gradient(stops: [
                    .init(color: .black.opacity(0), location: 0),
                    .init(color: .black, location: fade),
                    .init(color: .black, location: 1 - fade),
                    .init(color: .black.opacity(0), location: 1),
                ]),
                startPoint: .zero, endPoint: CGPoint(x: width, y: 0)))
        }
        let motion = River.motion(level: frame.level)
        let stops = River.crestStopOpacities(base: River.crestBase(blend: frame.crestBlend))
        let lastStop = Double(stops.count - 1)
        let gradient = Gradient(stops: stops.enumerated().map { index, opacity in
            .init(color: ink.opacity(opacity), location: Double(index) / lastStop)
        })
        for (index, strand) in Constants.riverStrands.enumerated() {
            var path = Path()
            path.addLines(River.strandPoints(strand, motion: motion, clock: frame.clock))
            let crestStart = River.crestOffset(time: time, strandIndex: index)
            var strandContext = context
            strandContext.opacity = River.strandOpacity(strand, level: frame.level, time: time, reduceMotion: reduceMotion)
            strandContext.stroke(
                path,
                with: .linearGradient(gradient,
                                      startPoint: CGPoint(x: crestStart, y: 0),
                                      endPoint: CGPoint(x: crestStart + Constants.riverCrestWidth, y: 0)),
                style: StrokeStyle(lineWidth: River.strandWidth(strand, level: frame.level), lineCap: .round, lineJoin: .round))
        }
    }
}

/// Holds the engine's frame between renders. A reference so the renderer can advance it
/// without invalidating the view; nothing observes it.
private final class RiverEngine {
    var frame = RiverIndicatorFrame()
}

/// The charcoal surface both HUD shapes share: near-opaque fill, two shadows, and on
/// dark appearance a hairline where the shadow disappears into dark windows.
struct HUDSurface<S: InsettableShape>: View {
    let shape: S
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        shape
            .fill(Color(nsColor: Palette.charcoal).opacity(isDark ? Constants.hudFillOpacityDark : Constants.hudFillOpacityLight))
            .overlay {
                if isDark {
                    shape.strokeBorder(.white.opacity(Constants.hudHairlineOpacity), lineWidth: Constants.hudHairlineWidth)
                }
            }
            .shadow(color: .black.opacity(Constants.hudNearShadowOpacity),
                    radius: Constants.hudNearShadowRadius, y: Constants.hudNearShadowOffset)
            .shadow(color: .black.opacity(Constants.hudFarShadowOpacity),
                    radius: Constants.hudFarShadowRadius, y: Constants.hudFarShadowOffset)
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
