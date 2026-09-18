import AppKit
import SwiftUI

/// River's color tokens (planning 0028), the one place the identity's colors are
/// spelled. Marks use `ink` only; the accent never touches the indicator or the menu bar.
enum Palette {
    static let charcoal = NSColor(srgbHex: 0x23262B)
    static let raisedCharcoal = NSColor(srgbHex: 0x2E3238)
    static let ink = NSColor(srgbHex: 0xECEEF1)

    // Vivid turquoise, OKLCH hue 196: 4.61:1 on white, 7.40:1 on charcoal.
    static let accentLight = NSColor(srgbHex: 0x148284)
    static let accentDark = NSColor(srgbHex: 0x31C8CA)
    static let accent = NSColor(name: "RiverAccent") { appearance in
        isDark(appearance) ? accentDark : accentLight
    }
    // Text on an accent ground: white passes on the light value; on the dark value it
    // measures 2.05:1, so charcoal instead.
    static let onAccent = NSColor(name: "RiverOnAccent") { appearance in
        isDark(appearance) ? charcoal : .white
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
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
