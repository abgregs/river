import AppKit
import Testing
@testable import River

@Suite("Palette")
struct PaletteTests {
    // The accent values were chosen for contrast (planning 0028); a drifted hex would
    // silently fail text on white or on charcoal, so each appearance is pinned.
    @Test("the accent resolves to the light value on aqua and the vivid value on dark aqua",
          arguments: [(NSAppearance.Name.aqua, 0x148284 as UInt32), (.darkAqua, 0x00E7E9)])
    func accentPerAppearance(appearance: NSAppearance.Name, hex: UInt32) throws {
        #expect(try resolvedHex(Palette.accent, in: appearance) == hex)
    }

    // White on #00E7E9 measures 1.54:1, so the dark appearance must put charcoal on the accent.
    @Test("text on the accent is white on aqua and charcoal on dark aqua",
          arguments: [(NSAppearance.Name.aqua, 0xFFFFFF as UInt32), (.darkAqua, 0x23262B)])
    func onAccentPerAppearance(appearance: NSAppearance.Name, hex: UInt32) throws {
        #expect(try resolvedHex(Palette.onAccent, in: appearance) == hex)
    }

    @Test("the mark tokens are the settled charcoal, raised and deep charcoal, and ink")
    func markTokens() throws {
        #expect(try resolvedHex(Palette.charcoal, in: .aqua) == 0x23262B)
        #expect(try resolvedHex(Palette.raisedCharcoal, in: .aqua) == 0x2E3238)
        #expect(try resolvedHex(Palette.deepCharcoal, in: .aqua) == 0x101215)
        #expect(try resolvedHex(Palette.ink, in: .darkAqua) == 0xECEEF1)
        #expect(try resolvedHex(Palette.mist, in: .aqua) == 0xF4F5F7)
    }

    // The floating UI follows Light and Dark mode on an opaque tint, so its ground is the tint
    // whatever the desktop. Text needs 4.5:1 on it; the mark draws in the text color, so it holds
    // the same. Secondary text is the text color at `hudSecondaryTextOpacity`, mixed over the
    // tint; the system `.secondary` (0.5) measured about 3.0:1 on the old translucent panel.
    @Test("the floating UI's text and mark hold contrast on its tint",
          arguments: [("dark", Palette.HUD.dark), ("light", Palette.HUD.light)])
    func hudContrast(name: String, colors: Palette.HUD) {
        let tint = channels(colors.tint)
        let grounds = [tint]
        let alpha = Constants.hudSecondaryTextOpacity
        for ground in grounds {
            let secondary = zip(channels(colors.text), ground).map { alpha * $0 + (1 - alpha) * $1 }
            #expect(contrast(channels(colors.text), ground) >= 4.5, "\(name) text on \(ground)")
            #expect(contrast(secondary, ground) >= 4.5, "\(name) secondary text on \(ground)")
        }
    }

    // Glass's frost veils the strokes as it forms while their ink rises under it. A veil the tint
    // moved toward the text color dims them part way, so they settle stronger than muted; a veil
    // past the tint, the light near-white of 2026-11-04, washed them back to muted and left the
    // frost unseen on the tint, so the entrance pulsed. One fraction in both appearances keeps
    // light's entrance and exit the same as dark's.
    @Test("Glass's veil is the tint moved toward the text color by the same fraction in each appearance")
    func glassVeilMirrorsAcrossAppearances() {
        func fraction(_ colors: Palette.HUD) -> [Double] {
            zip(zip(channels(colors.glassVeil), channels(colors.tint)), channels(colors.text)).map { ($0.0 - $0.1) / ($1 - $0.1) }
        }
        let dark = fraction(.dark)
        for value in dark + fraction(.light) { #expect(abs(value - dark[0]) < 0.01) }
        #expect(dark[0] > 0 && dark[0] < 0.5)
    }

    // The recording dot carries meaning, so it needs 3:1 against the bar behind it. The bar's
    // ground follows the wallpaper; these are modelled light and dark bars, each at the end of
    // its range nearest the red (a mid gray, and the lightest dark ground).
    @Test("the recording red holds 3:1 on the menu bar in each appearance",
          arguments: [(NSAppearance.Name.aqua, 0xB13546 as UInt32, 0xB8B8B8 as UInt32), (.darkAqua, 0xDD6871, 0x3A3B3D)])
    func recordingContrast(appearance: NSAppearance.Name, hex: UInt32, ground: UInt32) throws {
        #expect(try resolvedHex(Palette.recording, in: appearance) == hex)
        let red = channels(NSColor(srgbHex: hex)), bar = channels(NSColor(srgbHex: ground))
        #expect(contrast(red, bar) >= 3)
    }

    private func channels(_ color: NSColor) -> [Double] {
        let srgb = color.usingColorSpace(.sRGB)!
        return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent]
    }

    private func contrast(_ a: [Double], _ b: [Double]) -> Double {
        func luminance(_ c: [Double]) -> Double {
            let linear = c.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private func resolvedHex(_ color: NSColor, in name: NSAppearance.Name) throws -> UInt32 {
        let appearance = try #require(NSAppearance(named: name))
        var hex: UInt32 = 0
        appearance.performAsCurrentDrawingAppearance {
            guard let srgb = color.usingColorSpace(.sRGB) else { return }
            let channels = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent]
            hex = channels.reduce(0) { ($0 << 8) | UInt32(($1 * 255).rounded()) }
        }
        return hex
    }
}
