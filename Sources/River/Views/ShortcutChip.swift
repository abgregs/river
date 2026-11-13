import SwiftUI

/// A shortcut in its outline (planning 0036; shortcut recorder study, rounds 5 to 8): the keys
/// inside one hairline, as the Settings window shows every shortcut. While the recorder listens
/// the outline turns akane around a pulsing dot, with the held keys inside. A save holds the
/// new shortcut in red, then the dot fades as it shrinks and the red fades to the ink hairline
/// as the outline closes on the keys. The keys never move: the chip sits against its row's
/// trailing edge, so only its leading edge does.
struct ShortcutChip: View {
    enum Look: Equatable {
        case saved
        case recording
        case saving
    }

    /// The keys; nil for an empty recording chip, a square around the dot.
    let text: Text?
    var look: Look = .saved
    /// A refused attempt, shown dimmed.
    var isTried = false
    /// When recording began: the pulse's clock.
    var startedAt: Date = .distantPast

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringOpacity = 0.0
    @State private var dotOpacity = 0.0
    @State private var dotScale = 1.0
    @State private var dotBoxFraction = 0.0

    var body: some View {
        let ink = SettingsInk(colorScheme)
        let red = Color(nsColor: Palette.recording)
        let outline = RoundedRectangle(cornerRadius: 5, style: .continuous)
        HStack(spacing: 0) {
            if look != .saved {
                dot(red)
                    .frame(width: (text == nil ? 8 : 12) * dotBoxFraction, alignment: .trailing)
            }
            if let text {
                text
                    .font(.system(size: 13))
                    .tracking(0.13)
                    .opacity(isTried ? 0.45 : 1)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 20)
        .clipShape(outline)
        .overlay { outline.strokeBorder(ink.opacity(0.28), lineWidth: 0.5) }
        .overlay { outline.strokeBorder(red, lineWidth: 1).opacity(ringOpacity) }
        .fixedSize()
        .onAppear { settle(into: look, from: nil) }
        .onChange(of: look) { old, new in settle(into: new, from: old) }
    }

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
        .padding(.trailing, text == nil ? 1 : 5)
        .accessibilityHidden(true)
    }

    private func settle(into look: Look, from old: Look?) {
        switch look {
        case .recording:
            ringOpacity = 1
            dotOpacity = 1
            dotScale = 1
            dotBoxFraction = 1
        case .saving where old == .recording:
            save()
        case .saving, .saved:
            ringOpacity = 0
            dotOpacity = 0
            dotBoxFraction = 0
        }
    }

    // Brisk timing (Constants). Reduce Motion keeps the fades, drops the shrink, and closes the
    // outline in one step once the dot is nearly gone.
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
        if reduceMotion {
            let close = Constants.recorderSaveOutlineDelay + Constants.recorderSaveOutlineDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + close) { dotBoxFraction = 0 }
        } else {
            withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: Constants.recorderSaveOutlineDuration)
                .delay(Constants.recorderSaveOutlineDelay)) {
                dotBoxFraction = 0
            }
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
