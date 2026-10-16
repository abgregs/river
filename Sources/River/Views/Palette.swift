import AppKit
import SwiftUI

/// River's color tokens (planning 0028), the one place the identity's colors are
/// spelled. The panel's mark takes the accent while River records or transcribes
/// (docs/design/stones-identity.md); otherwise marks use `ink`.
enum Palette {
    static let charcoal = NSColor(srgbHex: 0x23262B)
    static let raisedCharcoal = NSColor(srgbHex: 0x2E3238)
    // Charcoal's hue, darker (OKLCH lightness 0.18): the floating UI's tint over its blur.
    // Charcoal itself is lighter than the blur over dark desktops, so it would lift them.
    static let deepCharcoal = NSColor(srgbHex: 0x101215)
    static let ink = NSColor(srgbHex: 0xECEEF1)
    // Charcoal's cool hue at near white: the light floating UI's tint over its blur.
    static let mist = NSColor(srgbHex: 0xF4F5F7)

    // Vivid turquoise, OKLCH hue 196: 4.61:1 on white. The dark value is the hue's most vivid
    // at lightness 0.84: 9.83:1 on charcoal, and 7.27:1 on the HUD's blurred surface over a
    // white page, its lightest ground.
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

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// The floating UI's colors for one appearance (docs/design/color.md, The HUD surface). The
    /// floating UI follows Light and Dark mode: dark is charcoal with ink and the bright accent,
    /// light is the same build with the two swapped and the deep accent.
    struct HUD {
        let tint: NSColor
        let tintOpacity: Double
        // Text, and the r while the model prepares.
        let text: NSColor
        // The mark while River records or transcribes.
        let accent: NSColor
        // The inner hairline is white in both; the outer line black.
        let hairlineOpacity: Double
        let hairlineTopOpacity: Double
        let outerLineOpacity: Double

        static let dark = HUD(
            tint: deepCharcoal, tintOpacity: Constants.hudDarkTintOpacity, text: ink, accent: accentDark,
            hairlineOpacity: Constants.hudDarkHairlineOpacity,
            hairlineTopOpacity: Constants.hudDarkHairlineTopOpacity, outerLineOpacity: Constants.hudDarkOuterLineOpacity)
        static let light = HUD(
            tint: mist, tintOpacity: Constants.hudLightTintOpacity, text: charcoal, accent: accentLight,
            hairlineOpacity: Constants.hudLightHairlineOpacity,
            hairlineTopOpacity: Constants.hudLightHairlineTopOpacity, outerLineOpacity: Constants.hudLightOuterLineOpacity)

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
