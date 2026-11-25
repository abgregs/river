import AppKit
import SwiftUI

/// Everything River floats above the Dock, as one bottom-anchored stack (planning 0028; the
/// mark is 川, docs/design/kawa-identity.md): the mark's panel, which carries only the
/// recording state, or in its place, once the panel has gone, the status: the model's while a
/// dictation waits for it (0004), held text, or a cycle error (0018); and above them the
/// streaming transcript (0025). It observes `AppState` only; every number that shapes the mark's
/// motion lives in the pure `KawaIndicatorTimeline` and `KawaIndicatorEngine`, and the ring's in
/// `StatusRing`; panel and focus behavior live in the coordinator.
struct RiverIndicatorView: View {
    let appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // The mark's current pass through the panel. It outlives the activity: the mark stays in the
    // stack until its exit has finished.
    @State private var markCycle: KawaIndicatorCycle?
    // The status drawn in the mark's place, and when the last panel finished leaving: a status
    // waits for the panel, then a beat, so the two never share the place (planning 0004).
    @State private var shown: DictationStatus?
    @State private var panelGone: Date?
    private let statusRing: StatusRingCycle?

    // `markCycle`, `shown` and `statusRing` are internal for testability: the snapshot harness
    // renders a single moment, so it hands in a cycle or a status already under way.
    init(appState: AppState, markCycle: KawaIndicatorCycle? = nil, shown: DictationStatus? = nil, statusRing: StatusRingCycle? = nil) {
        self.appState = appState
        self.statusRing = statusRing
        _markCycle = State(initialValue: markCycle)
        _shown = State(initialValue: shown)
    }

    /// The stack at its tallest: the transcript above the mark, and wide enough for the widest
    /// status. The window is this plus the shadow margin and never resizes, so nothing on screen
    /// moves under a transition.
    static let contentSize = CGSize(
        width: max(Constants.transcriptPanelWidth, Constants.statusRowMaxWidth),
        height: Constants.transcriptPanelHeight + Constants.hudStackSpacing + max(Constants.indicatorPanelHeight, Constants.statusRowHeight)
    )

    var body: some View {
        // Each surface takes space only while it shows. The bottom of the stack sits just above
        // the Dock: the mark's panel, or the status centred where it was, bottom edges aligned.
        VStack(spacing: Constants.hudStackSpacing) {
            // The transcript comes and goes with the cycle, as the other surfaces do; its shortcut
            // shows it quicker and hides it quicker still (planning 0034). Its animations stay on
            // it, so a state change never retimes the status's own fades below.
            VStack(spacing: 0) {
                if isTranscriptShown {
                    TranscriptPanelView(text: appState.liveTranscript)
                        .transition(fade)
                }
            }
            .animation(.easeOut(duration: Constants.hudFadeSeconds), value: appState.state)
            .animation(liveTextToggle, value: appState.isLiveTextShown)
            ZStack(alignment: .bottom) {
                if let markCycle {
                    // The mark runs its own entry and exit on the cycle's clock, so no SwiftUI
                    // transition or animation may also move it.
                    MarkPanel(cycle: markCycle, activity: activity, appState: appState)
                        .transition(.identity)
                        .transaction { $0.animation = nil }
                }
                if let shown {
                    StatusRow(status: shown, appState: appState, ring: statusRing)
                        .transition(fade)
                }
            }
        }
        .frame(width: Self.contentSize.width, height: Self.contentSize.height, alignment: .bottom)
        .padding(Constants.hudShadowMargin)
        .onChange(of: activity, initial: true) { updateMarkCycle() }
        .onChange(of: appState.isAudioFlowing) { updateMarkCycle() }
        .onChange(of: appState.dictationStatus) { _, status in updateShown(status) }
        .task(id: markCycle) { await removeMarkCycleWhenGone() }
        .task(id: StatusEntry(isWaiting: appState.dictationStatus != nil && shown == nil, panel: markCycle?.id)) {
            await showStatusWhenPanelGone()
        }
    }

    private var liveTextToggle: Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: appState.isLiveTextShown
                     ? Constants.liveTextShowSeconds : Constants.liveTextHideSeconds)
    }

    // Enter and exit: opacity with a 6 pt rise, ease-out both ways; a plain fade under Reduce Motion.
    private var fade: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: Constants.hudFadeRise))
    }

    // The status's entry and exit: the HUD's fade on the strong ease-out things arrive on.
    private var statusFade: Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: Constants.hudFadeSeconds)
    }

    // A status a new recording interrupts: a gentle ease-in-out, slow enough to read as a fade
    // while the panel comes in over it. The strong ease-out of an entry drops most of the
    // opacity in its first frames, which read as a cut at 0.1 s (maintainer, on device).
    private var interruptedFade: Animation {
        .timingCurve(0.37, 0, 0.63, 1, duration: Constants.statusInterruptedFadeSeconds)
    }

    private var isTranscriptShown: Bool {
        TranscriptPanelView.isVisible(state: appState.state, isShown: appState.isLiveTextShown)
    }

    private var activity: MarkActivity {
        MarkActivity.of(state: appState.state, hidesPanel: appState.hidesPanel)
    }

    private func updateMarkCycle() {
        let next = KawaIndicatorCycle.next(markCycle, activity: activity, isAudioFlowing: appState.isAudioFlowing,
                                           reduceMotion: reduceMotion, at: Date())
        // A new recording takes the place almost at once: a status still showing leaves on a
        // quick fade while the panel comes in.
        if let next, next.id != markCycle?.id, shown != nil {
            withAnimation(interruptedFade) { shown = nil }
        }
        markCycle = next
    }

    // A status shown changes in place; one that clears leaves on the fade. A new one waits for
    // `showStatusWhenPanelGone`.
    private func updateShown(_ status: DictationStatus?) {
        guard let status else {
            withAnimation(appState.state == .recording ? interruptedFade : statusFade) { shown = nil }
            return
        }
        if shown != nil { shown = status }
    }

    private struct StatusEntry: Equatable {
        let isWaiting: Bool
        let panel: UUID?
    }

    // A status enters once the mark's panel has gone and the beat has passed, or at once when
    // no panel has been up, as for a permission refused before a recording starts.
    private func showStatusWhenPanelGone() async {
        guard appState.dictationStatus != nil, shown == nil, markCycle == nil else { return }
        if let panelGone {
            let wait = panelGone.addingTimeInterval(Constants.statusEntryBeatSeconds).timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        }
        guard !Task.isCancelled, markCycle == nil, shown == nil, let status = appState.dictationStatus else { return }
        withAnimation(statusFade) { shown = status }
    }

    // A cycle whose text is typed, or whose dictation lets it go, leaves the stack when its exit
    // has finished. A new cycle replaces it first, which cancels the wait.
    private func removeMarkCycleWhenGone() async {
        guard let cycle = markCycle, let end = cycle.end(reduceMotion: reduceMotion) else { return }
        try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
        if !Task.isCancelled, markCycle == cycle {
            markCycle = nil
            panelGone = Date()
        }
    }
}

/// The panel around the mark, and the mark's accessible name: the strokes are decorative, so
/// the panel speaks the state and, while listening, the elapsed time. Its opacity and rise come
/// from the cycle's timeline.
private struct MarkPanel: View {
    let cycle: KawaIndicatorCycle
    let activity: MarkActivity
    // Read here, not by the stack above, so a level reading (about 14 a second) redraws only
    // the mark's panel, not the transcript above it.
    let appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var voice = KawaIndicatorVoice()
    @State private var recordingStart = Date()
    // True while nothing on the panel can move (a dead microphone, a long transcription), so the
    // timeline stops redrawing a still frame at display rate.
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
                .accessibilityHidden(activity == .rest)
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

/// The surface every floating shape shares (the mark's panel, the status, the
/// transcript panel): an opaque tint (charcoal in Dark mode, mist in Light), with one of two edges.
/// Opaque, so the panel looks the same over any desktop (maintainer, 2026-11-04).
///
/// - `.window`, the status and the live text: the Settings window's edge (docs/design/color.md,
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
