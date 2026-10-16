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

    // The floating UI follows Light and Dark mode, and its blur lets any desktop through. Text
    // needs 4.5:1 and the mark, a graphic that carries River's state, 3:1 on every ground the
    // panel can sit on. This models the worst case: the tint mixed straight over black, gray,
    // and white with the blur ignored (the blur pulls the ground toward the tint, so the
    // real panel only does better), plus the opaque tint Reduce Transparency draws. At the
    // dark tint's 0.72 a light panel over black left the deep accent at 2.13:1. Secondary text
    // is the text color at `hudSecondaryTextOpacity`, so it is mixed over the ground the same
    // way; the system `.secondary` (0.5) measured about 3.0:1 here.
    @Test("the floating UI's text and mark hold contrast over any desktop",
          arguments: [("dark", Palette.HUD.dark), ("light", Palette.HUD.light)])
    func hudContrast(name: String, colors: Palette.HUD) {
        let tint = channels(colors.tint)
        let grounds = [0.0, 0.5, 1.0].map { desktop in tint.map { colors.tintOpacity * $0 + (1 - colors.tintOpacity) * desktop } } + [tint]
        let alpha = Constants.hudSecondaryTextOpacity
        for ground in grounds {
            let secondary = zip(channels(colors.text), ground).map { alpha * $0 + (1 - alpha) * $1 }
            #expect(contrast(channels(colors.text), ground) >= 4.5, "\(name) text on \(ground)")
            #expect(contrast(secondary, ground) >= 4.5, "\(name) secondary text on \(ground)")
            #expect(contrast(channels(colors.accent), ground) >= 3, "\(name) accent on \(ground)")
        }
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
