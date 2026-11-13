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

    // Glass mirrors between the appearances, so Light shows what Dark shows. The veil is the tint
    // moved toward the text color: the light near-white of 2026-11-04 sat past the tint and never
    // showed as the frost formed. A ripple's lit side is the text color and its far side the tint
    // pushed away from it: light's white light barely showed on the near-white tint.
    @Test("Glass's veil and ripple colors mirror between the appearances")
    func glassMirrorsAcrossAppearances() {
        // How far `color` sits from the tint toward `pole`, per channel.
        func fraction(_ color: NSColor, of colors: Palette.HUD, toward pole: NSColor) -> [Double] {
            zip(zip(channels(color), channels(colors.tint)), channels(pole)).map { ($0.0 - $0.1) / ($1 - $0.1) }
        }
        let veil = fraction(Palette.HUD.dark.glassVeil, of: .dark, toward: Palette.HUD.dark.text)
        #expect(veil[0] > 0 && veil[0] < 0.5)
        for value in veil + fraction(Palette.HUD.light.glassVeil, of: .light, toward: Palette.HUD.light.text) {
            #expect(abs(value - veil[0]) < 0.01)
        }
        // The far side is a blend (`NSColor.blended`, which does not mix in sRGB), so it is held
        // to its side of the tint, away from the text color, rather than to one sRGB fraction.
        for (colors, pole) in [(Palette.HUD.dark, NSColor.black), (.light, .white)] {
            for value in fraction(colors.glassShade, of: colors, toward: pole) { #expect(value > 0.1 && value < 1) }
            // Light's is lifted toward the tint (`kawaGlassLightHighlightInk`), but stays nearer the text.
            for value in fraction(colors.glassHighlight, of: colors, toward: colors.text) { #expect(value > 0.5 && value <= 1.0001) }
        }
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

    // The recorder's dot and red outline carry "recording", so each needs 3:1 on the Settings
    // window's tint in its appearance (color.md, Status colors; 5.55:1 and 5.62:1).
    @Test("the recording red holds 3:1 on the Settings window's tint in each appearance",
          arguments: [(NSAppearance.Name.aqua, 0xF4F5F7 as UInt32), (.darkAqua, 0x101215)])
    func recordingContrastInSettings(appearance: NSAppearance.Name, tint: UInt32) throws {
        #expect(try resolvedHex(Palette.windowTint, in: appearance) == tint)
        let red = channels(NSColor(srgbHex: try resolvedHex(Palette.recording, in: appearance)))
        #expect(contrast(red, channels(NSColor(srgbHex: tint))) >= 3)
    }

    private func channels(_ color: NSColor) -> [Double] {
        let srgb = color.usingColorSpace(.sRGB)!
        return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent]
    }

    // One edge with the Settings window (color.md, round 12): the dark indicator's 1 pt rim
    // reached 93 % white and outshone the window beside it. Its rim is now the window's inner
    // line, and may fade below it but never rise above it.
    @Test("the dark indicator's rim is never brighter or wider than the window's edge")
    func darkRimNeverOutshinesTheWindow() {
        let dark = Palette.HUD.dark
        #expect(dark.rim.width == Constants.hudInnerLineWidth)
        #expect(dark.rim.stops.allSatisfy { $0.opacity <= dark.innerLineOpacity })
        #expect(dark.rim.farShadeOpacity == nil)
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
