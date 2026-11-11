import AppKit
import SwiftUI

/// Everything River floats above the Dock, as one bottom-anchored stack (planning 0028; the
/// mark is 川, docs/design/kawa-identity.md): the mark's panel, which carries only the
/// recording state;
/// above it one rounded rectangle for the error toast (0018), the model-loading label
/// (0004), and the live-reconfiguration notice; and above that the streaming transcript
/// (0025). It observes `AppState` only; every number that shapes the mark's motion lives in
/// the pure `KawaIndicatorTimeline` and `KawaIndicatorEngine`, and panel and focus behavior
/// live in the coordinator.
struct RiverIndicatorView: View {
    let appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    // The mark's current pass through the panel. It outlives the activity: the mark stays in the
    // stack until its exit has finished.
    @State private var markCycle: KawaIndicatorCycle?

    // `markCycle` is internal for testability: the snapshot harness renders a single moment, so
    // it hands in a cycle already under way.
    init(appState: AppState, markCycle: KawaIndicatorCycle? = nil) {
        self.appState = appState
        _markCycle = State(initialValue: markCycle)
    }

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
            if let markCycle {
                // The mark runs its own entry and exit on the cycle's clock, so no SwiftUI
                // transition or animation may also move it.
                MarkPanel(cycle: markCycle, activity: activity, appState: appState)
                    .transition(.identity)
                    .transaction { $0.animation = nil }
            }
        }
        .frame(width: Self.contentSize.width, height: Self.contentSize.height, alignment: .bottom)
        .padding(Constants.hudShadowMargin)
        .onChange(of: activity, initial: true) { updateMarkCycle() }
        .onChange(of: appState.isAudioFlowing) { updateMarkCycle() }
        .task(id: markCycle) { await removeMarkCycleWhenGone() }
        // A message left after the cycle drops into the mark's place once the mark has gone.
        .animation(.easeOut(duration: Constants.hudFadeSeconds), value: markCycle == nil)
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

    // While the model gets ready the panel holds the muted strokes, not a spinner.
    private var activity: MarkActivity {
        MarkActivity.of(state: appState.state, isModelPreparing: loadingLabel != nil)
    }

    // A notice belongs to the recording it describes: showing one at `.idle` would put
    // last cycle's message under a capsule that is on its way out (planning 0017's
    // canceled-notice bleed). The menu row stays its lingering home.
    private var notice: String? {
        appState.state == .recording ? appState.notice : nil
    }

    private func updateMarkCycle() {
        markCycle = KawaIndicatorCycle.next(markCycle, activity: activity, isAudioFlowing: appState.isAudioFlowing,
                                            reduceMotion: reduceMotion, at: Date())
    }

    // A cycle whose text is typed leaves the stack when its exit has finished. A new cycle
    // replaces it first, which cancels the wait.
    private func removeMarkCycleWhenGone() async {
        guard let cycle = markCycle, let end = cycle.end(reduceMotion: reduceMotion) else { return }
        try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
        if !Task.isCancelled, markCycle == cycle { markCycle = nil }
    }

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
                    .foregroundStyle(.foreground.opacity(Constants.hudSecondaryTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Constants.hudMessagePadding)
        // The preparing label alone hugs its text and centers under the mark; toasts and
        // notices keep the full width their wrapped prose needs.
        .frame(width: isPreparingLabelOnly ? nil : Constants.hudMessageWidth, alignment: .leading)
        .foregroundStyle(Color(nsColor: Palette.HUD.for(colorScheme).text))
        .modifier(HUDSurface(cornerRadius: Constants.hudMessageCornerRadius, edge: .window))
        .accessibilityElement(children: .combine)
    }
}

/// The panel around the mark, and the mark's accessible name: the strokes are decorative, so
/// the panel speaks the state and, while listening, the elapsed time. While preparing, the
/// label above speaks instead. Its opacity and rise come from the cycle's timeline.
private struct MarkPanel: View {
    let cycle: KawaIndicatorCycle
    let activity: MarkActivity
    // Read here, not by the stack above, so a level reading (about 14 a second) redraws only
    // the mark's panel, not the transcript and messages beside it.
    let appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var voice = KawaIndicatorVoice()
    @State private var recordingStart = Date()
    // True while nothing on the panel can move (preparing, a dead microphone), so the timeline
    // stops redrawing a still frame at display rate; a model download can take minutes.
    @State private var isStill = false

    var body: some View {
        TimelineView(.animation(paused: isStill)) { context in
            let time = cycle.time(at: context.date)
            let channels = KawaIndicatorTimeline.channels(at: time, events: cycle.events, reduceMotion: reduceMotion)
            let engine = voice.engine(for: cycle.id, events: cycle.events, at: time, inputLevel: Double(appState.inputLevel),
                                      reduceMotion: reduceMotion)
            KawaMarkPanelFace(channels: channels, time: time, reduceMotion: reduceMotion, engine: engine)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(activity == .transcribing ? "Transcribing" : "Listening")
                .accessibilityValue(activity == .listening ? elapsed(at: context.date) : "")
                .accessibilityHidden(activity == .rest || activity == .preparing)
        }
        .onChange(of: activity, initial: true) { _, newActivity in
            if newActivity == .listening { recordingStart = Date() }
        }
        .task(id: cycle) { await pauseWhenStill() }
    }

    // Any change to the cycle restarts this, so the next event always finds the timeline running.
    private func pauseWhenStill() async {
        isStill = false
        guard let still = KawaIndicatorTimeline.stillFrom(cycle.events) else { return }
        try? await Task.sleep(for: .seconds(max(0, still - cycle.time(at: Date()))))
        if !Task.isCancelled { isStill = true }
    }

    private func elapsed(at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(recordingStart)))
        return Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }
}

/// The mark's panel at one moment: 川 and Glass on the panel's surface, at the opacity and rise
/// the timeline gives it. Shared by the live panel and the snapshot harness, so a held frame is
/// the shipped panel, not a copy.
struct KawaMarkPanelFace: View {
    let channels: KawaIndicatorChannels
    let time: Double
    let reduceMotion: Bool
    let engine: KawaIndicatorEngine
    var glassLibrary: ShaderLibrary? = GlassRenderer.library
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let face = KawaMarkFrame(channels: channels, time: time, reduceMotion: reduceMotion, engine: engine, glassLibrary: glassLibrary)
            .frame(width: Constants.indicatorPanelWidth, height: Constants.indicatorPanelHeight)
            .modifier(HUDSurface(cornerRadius: Constants.indicatorPanelCornerRadius, edge: .lit))
        // The opacity reaches each of the surface's layers on its own, so where they stack, at
        // the rim, the edge outlasts the fill. In Light mode the bright rim then stood out over a
        // dark desktop as the panel left (maintainer, on device, 2026-11-04), so the light panel
        // is flattened first and fades as one. Dark mode fades as it was approved.
        Group {
            if colorScheme == .light { face.compositingGroup() } else { face }
        }
        .opacity(channels.panel)
        .offset(y: channels.rise)
    }
}

/// One frame of 川 and Glass, drawn from the timeline's channels and the engine.
struct KawaMarkFrame: View {
    let channels: KawaIndicatorChannels
    let time: Double
    let reduceMotion: Bool
    let engine: KawaIndicatorEngine
    var glassLibrary: ShaderLibrary? = GlassRenderer.library
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = Palette.HUD.for(colorScheme)
        Group {
            if let glassLibrary {
                Canvas { context, _ in GlassRenderer.drawStrokes(in: &context, channels: channels, colors: colors) }
                    .layerEffect(GlassRenderer.shader(glassLibrary, channels: channels, time: time, engine: engine,
                                                      reduceMotion: reduceMotion, colors: colors),
                                 maxSampleOffset: GlassRenderer.maxSampleOffset)
                    // Stops inside the rim, so the frost never covers the panel's edge.
                    .clipShape(RoundedRectangle(cornerRadius: Constants.indicatorPanelCornerRadius, style: .continuous)
                        .inset(by: Constants.hudRimWidth))
            } else {
                Canvas { context, _ in KawaMutedStrokes.draw(in: &context, presence: channels.muted, colors: colors) }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The surface every floating shape shares (the mark's panel, the message rectangle, the
/// transcript panel): an opaque tint (charcoal in Dark mode, mist in Light), with one of two edges.
/// Opaque, so the panel looks the same over any desktop (maintainer, 2026-11-04).
///
/// - `.window`, the message and the live text: the Settings window's edge (docs/design/color.md,
///   one edge with the Settings window), with no sheen, rim or inner shade. A dark surface adds a
///   light inner line; an outer line and the window's two shadows hold the edge.
/// - `.lit`, the mark's panel: a solid sheet of glass lit from the upper left, where Glass lights
///   its ripples from (Constants, the lit edge). Under the content: two shadows falling straight
///   down, the tint, and a sheen from the lit corner. Over it, so neither the frost nor anything
///   else covers the edge: a soft shade inside the far edges, the rim, and the outer line.
struct HUDSurface: ViewModifier {
    enum Edge { case window, lit }

    let cornerRadius: Double
    let edge: Edge
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let colors = Palette.HUD.for(colorScheme)
        content
            .background {
                ZStack {
                    shape.fill(Color(nsColor: colors.tint))
                    if edge == .lit {
                        GeometryReader { proxy in shape.fill(Self.sheen(colors, size: proxy.size)) }
                    }
                }
                .background {
                    switch edge {
                    case .lit: Self.litShadows(shape)
                    case .window: Self.windowShadows(shape, colors: colors)
                    }
                }
            }
            .overlay {
                ZStack {
                    switch edge {
                    case .lit:
                        Self.innerShade(shape, opacity: colors.innerShadeOpacity * Constants.hudFarEdgeShade)
                        GeometryReader { proxy in
                            shape.strokeBorder(Self.rim(colors.rim, size: proxy.size), lineWidth: colors.rim.width)
                        }
                    case .window:
                        shape.strokeBorder(.white.opacity(colors.innerLineOpacity), lineWidth: Constants.hudInnerLineWidth)
                    }
                    shape.inset(by: -Constants.hudOuterLineWidth)
                        .strokeBorder(.black.opacity(colors.outerLineOpacity), lineWidth: Constants.hudOuterLineWidth)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }

    /// The way the light travels across every floating surface, and across Glass's ripples, as
    /// a unit vector in view coordinates, from `Constants.hudLightAngle`: the one light they share.
    static let lightDirection: CGVector = {
        let angle = Constants.hudLightAngle * .pi / 180
        // CSS angles turn clockwise from up; the view's y grows downward.
        return CGVector(dx: sin(angle), dy: -cos(angle))
    }()

    /// Where a CSS linear gradient at `Constants.hudLightAngle` starts and ends on a box of
    /// `size`, as unit points: its line runs through the centre, and its ends are where the
    /// perpendiculars through the corners cross it, so 0 falls on the lit corner and 1 on the far
    /// one whatever the box's proportions. A fixed pair of unit points would tilt the light with
    /// the shape, and the three surfaces would each be lit from a different place.
    static func lightAxis(in size: CGSize) -> (start: UnitPoint, end: UnitPoint) {
        guard size.width > 0, size.height > 0 else { return (.topLeading, .bottomTrailing) }
        let dx = lightDirection.dx, dy = lightDirection.dy
        let half = (abs(size.width * dx) + abs(size.height * dy)) / 2
        let x = dx * half / size.width, y = dy * half / size.height
        return (UnitPoint(x: 0.5 - x, y: 0.5 - y), UnitPoint(x: 0.5 + x, y: 0.5 + y))
    }

    // White light along the rim from the lit corner, ending in the far-edge shade when the rim
    // has one.
    private static func rim(_ rim: Palette.HUD.Rim, size: CGSize) -> LinearGradient {
        var stops = rim.stops.map { Gradient.Stop(color: .white.opacity($0.opacity), location: $0.location) }
        if let shade = rim.farShadeOpacity { stops.append(.init(color: .black.opacity(shade), location: 1)) }
        let axis = lightAxis(in: size)
        return LinearGradient(stops: stops, startPoint: axis.start, endPoint: axis.end)
    }

    private static func sheen(_ colors: Palette.HUD, size: CGSize) -> LinearGradient {
        let axis = lightAxis(in: size)
        return LinearGradient(
            stops: [.init(color: .white.opacity(min(1, colors.sheenOpacity * Constants.hudSheen)), location: 0),
                    .init(color: .white.opacity(0), location: Constants.hudSheenReach)],
            startPoint: axis.start, endPoint: axis.end)
    }

    // An inner shadow: a band of black just outside the edge, moved toward the light so it
    // reaches inside the far edges, blurred, and seen only inside the shape. The band is wide
    // enough that the blur never shows its outer side.
    private static func innerShade(_ shape: RoundedRectangle, opacity: Double) -> some View {
        let band = 4 * Constants.hudInnerShadeRadius + max(abs(Constants.hudInnerShadeOffsetX), abs(Constants.hudInnerShadeOffsetY))
        return shape.inset(by: -band)
            .strokeBorder(.black.opacity(min(1, opacity)), lineWidth: band)
            .offset(x: Constants.hudInnerShadeOffsetX, y: Constants.hudInnerShadeOffsetY)
            .blur(radius: Constants.hudInnerShadeRadius)
            .mask(shape)
    }

    private static func litShadows(_ shape: RoundedRectangle) -> some View {
        let strength = Constants.hudShadowStrength
        return outsideOnly(shape, shadows: [
            (Constants.hudShadowOpacity * strength, Constants.hudShadowRadius, Constants.hudShadowOffset),
            (Constants.hudContactShadowOpacity * strength, Constants.hudContactShadowRadius, Constants.hudContactShadowOffset),
        ])
    }

    private static func windowShadows(_ shape: RoundedRectangle, colors: Palette.HUD) -> some View {
        outsideOnly(shape, shadows: zip(colors.windowShadowOpacities, zip(Constants.hudWindowShadowRadii, Constants.hudWindowShadowOffsets))
            .map { ($0, $1.0, $1.1) })
    }

    // Shadows with the shape cut out of them, so they only ever show outside the edge: the black
    // shape that casts each would otherwise fringe the tint's antialiased edge. Each is cast by
    // its own shape: a second `.shadow` on the first would shadow the first shadow too.
    private static func outsideOnly(_ shape: RoundedRectangle, shadows: [(opacity: Double, radius: Double, y: Double)]) -> some View {
        // The mask reaches past the farthest shadow, about three radii beyond its offset, so it
        // never cuts one off.
        let reach = shadows.map { 3 * $0.radius + abs($0.y) }.max() ?? 0
        return ZStack {
            ForEach(shadows.indices, id: \.self) { i in
                shape.fill(.black)
                    .shadow(color: .black.opacity(shadows[i].opacity), radius: shadows[i].radius, y: shadows[i].y)
            }
        }
        .mask {
            Rectangle()
                .padding(-reach)
                .overlay { shape.blendMode(.destinationOut) }
                .compositingGroup()
        }
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
                .foregroundStyle(.foreground.opacity(Constants.hudSecondaryTextOpacity))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
