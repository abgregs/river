import SwiftUI

/// A shortcut in its outline (planning 0036; shortcut recorder study, rounds 5 to 8): the keys
/// inside one hairline, as the Settings window shows every shortcut. While the recorder listens
/// the outline turns akane around a pulsing dot, with the held keys inside. A save holds the
/// new shortcut in red, then the dot fades as it shrinks and the red fades to the ink hairline
/// as the outline closes on the keys. The keys never move: the chip sits against its row's
/// trailing edge, so only its leading edge does. A shortcut that can be empty carries a clear
/// mark inside the trailing edge at rest; the outline opens over it to the right as a save
/// settles, into space the chip keeps free, so the keys still stay put.
struct ShortcutChip: View {
    /// The clear mark: its VoiceOver label and what a click does.
    struct Clear {
        let label: String
        let action: () -> Void
    }

    enum Look: Equatable {
        case saved
        case recording
        case saving
    }

    /// The keys; none for an empty recording chip, a square around the dot.
    let keys: ShortcutText.Keys
    var look: Look = .saved
    /// A refused attempt, shown dimmed.
    var isTried = false
    /// When recording began: the pulse's clock.
    var startedAt: Date = .distantPast
    /// What VoiceOver reads for the keys; nil leaves the chip's text to its container.
    var spoken: String?
    /// The clear mark, for a row that can be empty.
    var clear: Clear?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringOpacity = 0.0
    @State private var dotOpacity = 0.0
    @State private var dotScale = 1.0
    @State private var dotBoxFraction = 0.0
    @State private var clearFraction = 0.0

    var body: some View {
        let ink = SettingsInk(colorScheme)
        let red = Color(nsColor: Palette.recording)
        let outline = RoundedRectangle(cornerRadius: 5, style: .continuous)
        HStack(spacing: 0) {
            if look != .saved {
                dot(red)
                    .frame(width: (isEmpty ? 8 : 12) * dotBoxFraction, alignment: .trailing)
            }
            if !isEmpty {
                HStack(spacing: Constants.recorderKeySpacing) {
                    if let side = keys.side {
                        // A lone modifier names its side at the description's strength.
                        Text(side).foregroundStyle(ink.secondary)
                            .padding(.trailing, 3 - Constants.recorderKeySpacing)
                    }
                    ForEach(Array(keys.keys.enumerated()), id: \.offset) { _, key in Text(key) }
                }
                .font(.system(size: 13))
                .tracking(0.13)
                .opacity(isTried ? 0.45 : 1)
            }
        }
        .modifier(Spoken(label: spoken))
        .overlay(alignment: .trailing) {
            // Outside the keys' layout, so opening its box moves the outline, not the keys.
            if let clear { ClearMark(clear: clear, ink: ink).opacity(clearFraction).offset(x: Self.clearBox) }
        }
        .padding(.leading, 6)
        .padding(.trailing, 6 + (clear == nil ? 0 : Self.clearWidth * clearFraction))
        .frame(height: 20)
        .clipShape(outline)
        .overlay { outline.strokeBorder(ink.opacity(0.28), lineWidth: 0.5) }
        .overlay { outline.strokeBorder(red, lineWidth: 1).opacity(ringOpacity) }
        // The room the clear mark opens into, kept free while it is shut.
        .padding(.trailing, clear == nil ? 0 : Self.clearWidth * (1 - clearFraction))
        .fixedSize()
        .onAppear { settle(into: look, from: nil) }
        .onChange(of: look) { old, new in settle(into: new, from: old) }
    }

    private var isEmpty: Bool { keys.side == nil && keys.keys.isEmpty }

    // The clear mark's box: a 12 pt circle 4 pt after the keys. The outline then sits 4 pt past
    // the circle, as the circle sits 4 pt from its top and bottom, so the chip grows by 14 pt.
    static let clearBox: Double = 16
    static let clearWidth: Double = 14

    // The dot, 6 pt so its halo fits inside the 20 pt outline, pinned to the keys: as its box
    // closes it stays put and the outline's leading edge passes over it.
    private func dot(_ red: Color) -> some View {
        TimelineView(.animation(paused: look != .recording || reduceMotion)) { timeline in
            let halo = Self.halo(at: timeline.date.timeIntervalSince(startedAt))
            Circle()
                .fill(red)
                .frame(width: 6, height: 6)
                .background { Circle().fill(red).scaleEffect(halo.scale).opacity(reduceMotion ? 0 : halo.opacity) }
        }
        .frame(width: 6, height: 6)
        .scaleEffect(dotScale)
        .opacity(dotOpacity)
        .padding(.trailing, isEmpty ? 1 : 5)
        .accessibilityHidden(true)
    }

    private func settle(into look: Look, from old: Look?) {
        switch look {
        case .recording:
            ringOpacity = 1
            dotOpacity = 1
            dotScale = 1
            dotBoxFraction = 1
            clearFraction = 0
        case .saving where old == .recording:
            save()
        case .saving, .saved:
            ringOpacity = 0
            dotOpacity = 0
            dotBoxFraction = 0
            clearFraction = 1
        }
    }

    // Brisk timing (Constants). Reduce Motion keeps the fades and drops the shrink and the
    // closing outline: the outline closes in one step when the recorder settles at the save's
    // end, so a new recording, which cancels that settle, can't be closed by the old save.
    private func save() {
        withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: Constants.recorderSaveDotDuration)
            .delay(Constants.recorderSaveDotDelay)) {
            dotOpacity = 0
            if !reduceMotion { dotScale = 0.25 }
        }
        withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: Constants.recorderSaveOutlineDuration)
            .delay(Constants.recorderSaveOutlineDelay)) {
            ringOpacity = 0
        }
        guard !reduceMotion else { return }
        withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: Constants.recorderSaveOutlineDuration)
            .delay(Constants.recorderSaveOutlineDelay)) {
            dotBoxFraction = 0
            clearFraction = 1
        }
    }

    /// The pulse at `elapsed` seconds into recording: a ring of the dot's red widens and fades
    /// over the first 70 % of each period on a strong ease-out, then rests while the dot stays.
    static func halo(at elapsed: TimeInterval) -> (scale: Double, opacity: Double) {
        let phase = max(0, elapsed).truncatingRemainder(dividingBy: Constants.recorderPulsePeriod) / Constants.recorderPulsePeriod
        guard phase < 0.7 else { return (Constants.recorderPulseScale, 0) }
        let eased = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.23, y: 1), endControlPoint: UnitPoint(x: 0.32, y: 1))
            .value(at: phase / 0.7)
        return (1 + (Constants.recorderPulseScale - 1) * eased, Constants.recorderPulseOpacity * (1 - eased))
    }
}

/// The clear mark: one click empties the row (planning 0036). Dimmer than the keys, so the
/// shortcut reads first; full ink under the pointer.
private struct ClearMark: View {
    let clear: ShortcutChip.Clear
    let ink: SettingsInk
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: clear.action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(ink.opacity(isEnabled ? (isHovered ? 0.6 : 0.35) : 0.18))
                .frame(width: ShortcutChip.clearBox, height: 20, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Clear")
        .accessibilityLabel(clear.label)
    }
}

// The keys as one VoiceOver element, when the chip is told what to read.
private struct Spoken: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label {
            content.accessibilityElement(children: .ignore).accessibilityLabel(label)
        } else {
            content
        }
    }
}

/// One shake for each refusal: the outline moves -4, 4, -3, 2 pt and back as `animatableData`
/// rises by one (shortcut recorder study, round 1).
struct RefusalShake: GeometryEffect {
    var animatableData: Double

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offsets: [Double] = [0, -4, 4, -3, 2, 0]
        let position = (animatableData - animatableData.rounded(.down)) * Double(offsets.count - 1)
        let index = min(Int(position), offsets.count - 2)
        let x = offsets[index] + (offsets[index + 1] - offsets[index]) * (position - Double(index))
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}
