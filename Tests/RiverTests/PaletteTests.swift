import AppKit
import Testing
@testable import River

@Suite("Palette")
struct PaletteTests {
    // The accent values were chosen for contrast (planning 0028); a drifted hex would
    // silently fail text on white or on charcoal, so each appearance is pinned.
    @Test("the accent resolves to the light value on aqua and the vivid value on dark aqua",
          arguments: [(NSAppearance.Name.aqua, 0x148284 as UInt32), (.darkAqua, 0x31C8CA)])
    func accentPerAppearance(appearance: NSAppearance.Name, hex: UInt32) throws {
        #expect(try resolvedHex(Palette.accent, in: appearance) == hex)
    }

    // White on #31C8CA measures 2.05:1, so the dark appearance must put charcoal on the accent.
    @Test("text on the accent is white on aqua and charcoal on dark aqua",
          arguments: [(NSAppearance.Name.aqua, 0xFFFFFF as UInt32), (.darkAqua, 0x23262B)])
    func onAccentPerAppearance(appearance: NSAppearance.Name, hex: UInt32) throws {
        #expect(try resolvedHex(Palette.onAccent, in: appearance) == hex)
    }

    @Test("the mark tokens are the settled charcoal, raised charcoal, and ink")
    func markTokens() throws {
        #expect(try resolvedHex(Palette.charcoal, in: .aqua) == 0x23262B)
        #expect(try resolvedHex(Palette.raisedCharcoal, in: .aqua) == 0x2E3238)
        #expect(try resolvedHex(Palette.ink, in: .darkAqua) == 0xECEEF1)
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
