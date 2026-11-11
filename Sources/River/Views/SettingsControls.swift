import SwiftUI

// River's own controls in the Settings window (planning 0036; settings panel study, round 14).
// Monochrome, like the HUD: strengths of the text color do all the work, and solid ink means a
// setting is on. The menus they open, the focus ring and selected text keep the system's accent.

/// The text color at a strength, for the Settings window's tint.
struct SettingsInk {
    let color: Color

    init(_ scheme: ColorScheme) {
        color = Color(nsColor: Palette.HUD.for(scheme).text)
    }

    func opacity(_ value: Double) -> Color { color.opacity(value) }
    var secondary: Color { color.opacity(Constants.hudSecondaryTextOpacity) }
}

/// One setting: its label and control on a line, its description under them, and a hairline
/// above every row but the first.
struct SettingsRow<Control: View>: View {
    let label: String
    var description: Text?
    var divider = true
    @ViewBuilder let control: () -> Control
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let ink = SettingsInk(colorScheme)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 16) {
                Text(label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                control()
            }
            .frame(minHeight: 22)
            if let description {
                description
                    .font(.system(size: 11))
                    .lineSpacing(1)
                    .foregroundStyle(ink.secondary)
                    .frame(maxWidth: 380, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 38)
        .overlay(alignment: .top) {
            if divider { Rectangle().fill(ink.opacity(0.08)).frame(height: 1) }
        }
    }
}

/// The on/off switch: an ink track when on, a faint one when off.
struct RiverSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        RiverSwitch(configuration: configuration)
    }

    private struct RiverSwitch: View {
        let configuration: Configuration
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let ink = SettingsInk(colorScheme)
            let isOn = configuration.isOn
            let knobOff: Color = colorScheme == .dark ? ink.color : .white
            Button {
                configuration.isOn.toggle()
            } label: {
                Capsule()
                    .fill(isOn ? ink.color : ink.opacity(0.16))
                    .frame(width: 30, height: 17)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle()
                            .fill(isOn ? Color(nsColor: Palette.windowTint) : knobOff)
                            .shadow(color: .black.opacity(!isOn && colorScheme == .light ? 0.18 : 0), radius: 1, y: 1)
                            .overlay { Circle().strokeBorder(.black.opacity(isOn ? 0 : colorScheme == .dark ? 0.4 : 0.14), lineWidth: 0.5) }
                            .frame(width: 14, height: 14)
                            .padding(1.5)
                    }
                    .animation(reduceMotion ? nil : .timingCurve(0.2, 0, 0, 1, duration: 0.16), value: isOn)
            }
            .buttonStyle(.plain)
            .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
        }
    }
}

/// A button in River's bezel: a faint ink plate with a hairline, darker on hover and press.
struct RiverBezelButtonStyle: ButtonStyle {
    var height: Double = 22
    var fontSize: Double = 13

    func makeBody(configuration: Configuration) -> some View {
        Bezel(configuration: configuration, height: height, fontSize: fontSize)
    }

    private struct Bezel: View {
        let configuration: Configuration
        let height: Double
        let fontSize: Double
        @Environment(\.colorScheme) private var colorScheme
        @State private var isHovered = false

        var body: some View {
            let ink = SettingsInk(colorScheme)
            let fill = configuration.isPressed ? 0.18 : isHovered ? 0.12 : 0.08
            configuration.label
                .font(.system(size: fontSize))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: height)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ink.opacity(fill)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(ink.opacity(0.16), lineWidth: 0.5))
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}

/// A pop-up: River's bezel showing the choice, opening the system's menu with a checkmark on it.
struct RiverPopUp<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 7) {
                Text(options.first { $0.value == selection }?.label ?? "")
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(SettingsInk(colorScheme).opacity(0.7))
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(RiverBezelButtonStyle())
        .fixedSize()
        .accessibilityLabel(title)
    }
}

/// A segmented choice: one plate per option in a faint track; the chosen one raised.
struct RiverSegmentedChoice<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let ink = SettingsInk(colorScheme)
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let chosen = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.label)
                        .font(.system(size: 12, weight: chosen ? .medium : .regular))
                        .foregroundStyle(chosen ? ink.color : ink.opacity(0.86))
                        .padding(.horizontal, 12)
                        .frame(height: 20)
                        .background {
                            if chosen {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(colorScheme == .dark ? ink.opacity(0.2) : .white)
                                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.14), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(ink.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(ink.opacity(0.1), lineWidth: 0.5))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// River's mark, filled, `height` tall: the version line's sign.
struct KawaMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(KawaMark.path(transform: KawaMark.transform(height: rect.height, centredAt: CGPoint(x: rect.midX, y: rect.midY))))
    }
}
