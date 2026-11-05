import AppKit
import SwiftUI

/// River's color tokens (planning 0028), the one place the identity's colors are
/// spelled. The mark is monochrome everywhere, the panel included
/// (docs/design/kawa-identity.md); the accent is the controls' tint.
enum Palette {
    static let charcoal = NSColor(srgbHex: 0x23262B)
    static let raisedCharcoal = NSColor(srgbHex: 0x2E3238)
    // Charcoal's hue, darker (OKLCH lightness 0.18): the dark floating UI's opaque tint.
    static let deepCharcoal = NSColor(srgbHex: 0x101215)
    static let ink = NSColor(srgbHex: 0xECEEF1)
    // Charcoal's cool hue at near white: the light floating UI's opaque tint.
    static let mist = NSColor(srgbHex: 0xF4F5F7)

    // Vivid turquoise, OKLCH hue 196: 4.61:1 on white. The dark value is the hue's most vivid
    // at lightness 0.84: 9.83:1 on charcoal.
    static let accentLight = NSColor(srgbHex: 0x148284)
    static let accentDark = NSColor(srgbHex: 0x00E7E9)
    static let accent = NSColor(name: "RiverAccent") { appearance in
        isDark(appearance) ? accentDark : accentLight
    }
    // Text on an accent ground: white passes on the light value; on the dark value it
    // measures 1.54:1, so charcoal instead.
    static let onAccent = NSColor(name: "RiverOnAccent") { appearance in
        isDark(appearance) ? charcoal : .white
    }

    // Akaneiro (茜色), madder red: the menu bar's recording dot while the microphone records,
    // and nothing else. On a light bar the madder itself, 3.05:1 even on a mid-gray ground; on a
    // dark bar the same hue lifted (OKLCH 0.66 0.147 17), 3.36:1 on the lightest dark ground.
    static let akane = NSColor(srgbHex: 0xB13546)
    static let akaneOnDark = NSColor(srgbHex: 0xDD6871)
    static let recording = NSColor(name: "RiverRecording") { appearance in
        isDark(appearance) ? akaneOnDark : akane
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    // `a` parts of `color` to `1 - a` of `ground`, opaque, in sRGB.
    private static func mix(_ color: NSColor, _ a: Double, over ground: NSColor) -> NSColor {
        let f = color.usingColorSpace(.sRGB)!, b = ground.usingColorSpace(.sRGB)!
        return NSColor(srgbRed: f.redComponent * a + b.redComponent * (1 - a), green: f.greenComponent * a + b.greenComponent * (1 - a),
                       blue: f.blueComponent * a + b.blueComponent * (1 - a), alpha: 1)
    }

    /// The floating UI's colors for one appearance (docs/design/color.md, The HUD surface). The
    /// floating UI follows Light and Dark mode: dark is charcoal with ink and the bright accent,
    /// light is the same build with the two swapped and the deep accent.
    struct HUD {
        let tint: NSColor
        // Text, and the mark.
        let text: NSColor
        // The lit edge (Constants, the lit edge): the rim's white at its three stops, the
        // shade at its far end, the sheen, the inner shade and the outer line, all black but
        // the rim and the sheen.
        let rimOpacities: [Double]
        let farEdgeShadeOpacity: Double
        let sheenOpacity: Double
        let innerShadeOpacity: Double
        let outerLineOpacity: Double
        // Glass (docs/design/kawa-identity.md): the frost's veil, the light a ripple catches and
        // the shade on its far side, with how strongly each of the last two shows.
        let glassVeil: NSColor
        let glassHighlight: NSColor
        let glassHighlightAmount: Double
        let glassShade: NSColor
        let glassShadeAmount: Double

        // Glass mirrors between the appearances. The veil is the tint moved toward the text
        // color, by one fraction in both, so the frost shows as it forms over either tint: the
        // near-white light veil never showed (2026-11-04). A ripple's lit side moves toward the
        // text color and its far side to the tint pushed away from it, so light's ripples show
        // as Dark's do, in charcoal: a white light on the near-white tint barely showed. Both of
        // light's sides are lifted toward the tint, which read too dark at full strength.
        private static let veilFraction = 0.16

        static let dark = HUD(
            tint: deepCharcoal, text: ink,
            rimOpacities: Constants.hudDarkRimOpacities, farEdgeShadeOpacity: Constants.hudDarkFarEdgeShadeOpacity,
            sheenOpacity: Constants.hudDarkSheenOpacity, innerShadeOpacity: Constants.hudDarkInnerShadeOpacity,
            outerLineOpacity: Constants.hudDarkOuterLineOpacity,
            glassVeil: mix(ink, veilFraction, over: deepCharcoal),
            glassHighlight: ink, glassHighlightAmount: Constants.kawaGlassDarkHighlightAmount,
            glassShade: deepCharcoal.blended(withFraction: 0.4, of: .black) ?? deepCharcoal,
            glassShadeAmount: Constants.kawaGlassDarkShadeAmount)
        static let light = HUD(
            tint: mist, text: charcoal,
            rimOpacities: Constants.hudLightRimOpacities, farEdgeShadeOpacity: Constants.hudLightFarEdgeShadeOpacity,
            sheenOpacity: Constants.hudLightSheenOpacity, innerShadeOpacity: Constants.hudLightInnerShadeOpacity,
            outerLineOpacity: Constants.hudLightOuterLineOpacity,
            glassVeil: mix(charcoal, veilFraction, over: mist),
            glassHighlight: mix(charcoal, Constants.kawaGlassLightHighlightInk, over: mist),
            glassHighlightAmount: Constants.kawaGlassLightHighlightAmount,
            glassShade: mist.blended(withFraction: Constants.kawaGlassLightShadeWhite, of: .white) ?? mist,
            glassShadeAmount: Constants.kawaGlassLightShadeAmount)

        static func `for`(_ scheme: ColorScheme) -> HUD { scheme == .dark ? dark : light }
    }
}

extension NSColor {
    convenience init(srgbHex hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
