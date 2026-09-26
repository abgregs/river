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
        // screen, and the window never resizes under an animating transition.
        VStack(spacing: Constants.hudStackSpacing) {
            MarkPanel(state: appState.state, inputLevel: Double(appState.inputLevel))
                .modifier(HUDFade(isVisible: appState.state != .idle, reduceMotion: reduceMotion))
            ZStack(alignment: .top) {
                if hasMessage {
                    messages
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: Constants.hudFadeRise)))
                }
            }
            .frame(width: Constants.hudMessageWidth, height: Constants.hudMessageReservedHeight, alignment: .top)
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

    // A notice belongs to the recording it describes: showing one at `.idle` would put
    // last cycle's message under a capsule that is on its way out (planning 0017's
    // canceled-notice bleed). The menu row stays its lingering home.
    private var notice: String? {
        appState.state == .recording ? appState.notice : nil
    }

    private var hasMessage: Bool {
        appState.toast != nil || loadingLabel != nil || notice != nil
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
            if let notice {
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

/// The panel around the mark, and the mark's accessible name: the pixels are decorative,
/// so the panel speaks the state and, while listening, the elapsed time.
private struct MarkPanel: View {
    let state: RiverState
    let inputLevel: Double
    @State private var recordingStart = Date()

    var body: some View {
        TimelineView(.animation(paused: state == .idle)) { context in
            PixelMarkView(state: state, inputLevel: inputLevel, date: context.date)
                .padding(.horizontal, Constants.indicatorPanelHorizontalPadding)
                .padding(.vertical, Constants.indicatorPanelVerticalPadding)
                .background {
                    HUDSurface(shape: RoundedRectangle(cornerRadius: Constants.indicatorPanelCornerRadius, style: .continuous))
                }
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

/// The pixel mark, drawn per display frame from the pure presentation functions.
private struct PixelMarkView: View {
    let state: RiverState
    let inputLevel: Double
    let date: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var engine = PixelMarkEngine()

    var body: some View {
        Canvas { context, _ in
            let now = date.timeIntervalSinceReferenceDate
            let frame = engine.frame.advanced(to: now, state: state, inputLevel: inputLevel, reduceMotion: reduceMotion)
            engine.frame = frame
            PixelMarkRenderer.draw(frame, increaseContrast: contrast == .increased, in: &context)
        }
        .frame(width: Constants.pixelMarkSize, height: Constants.pixelMarkSize)
        .accessibilityHidden(true)
        // A new cycle starts from the r at rest, not from wherever the last one was left
        // when the timeline paused at idle.
        .onChange(of: state) { oldState, _ in
            if oldState == .idle { engine.frame = PixelMarkFrame() }
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
