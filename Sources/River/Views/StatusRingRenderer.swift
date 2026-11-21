import AppKit
import SwiftUI

/// Draws a `StatusRingFrame` (planning 0004): the 14 pt grid scaled to fit the box, in `ink`
/// turning toward `akane` as far as the frame says. The check is always `ink` and the
/// exclamation mark `akane`, as the study draws them (docs/design/studies/preparing/
/// preparing-status-r10.html).
enum StatusRingRenderer {
    static func draw(_ frame: StatusRingFrame, in context: inout GraphicsContext, size: CGSize, ink: NSColor, akane: NSColor) {
        let scale = min(size.width, size.height) / StatusRing.grid
        let ring = mix(ink, akane, frame.akane)
        for layer in frame.layers where layer.opacity > 0.003 {
            var group = context
            group.opacity = min(1, layer.opacity)
            group.drawLayer { group in
                for mark in layer.marks { draw(mark, in: &group, scale: scale, ring: ring, ink: ink, akane: akane) }
            }
        }
    }

    /// `ink` moved toward `akane` by `amount`, in sRGB.
    static func mix(_ ink: NSColor, _ akane: NSColor, _ amount: Double) -> NSColor {
        guard amount > 0 else { return ink }
        guard amount < 1 else { return akane }
        guard let a = ink.usingColorSpace(.sRGB), let b = akane.usingColorSpace(.sRGB) else { return ink }
        func blend(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * amount }
        return NSColor(srgbRed: blend(a.redComponent, b.redComponent), green: blend(a.greenComponent, b.greenComponent),
                       blue: blend(a.blueComponent, b.blueComponent), alpha: blend(a.alphaComponent, b.alphaComponent))
    }

    private static func draw(_ mark: StatusRingFrame.Mark, in context: inout GraphicsContext, scale: Double,
                             ring: NSColor, ink: NSColor, akane: NSColor) {
        let width = Constants.statusRingStroke * scale
        let round = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        func path(_ path: CGPath) -> Path { Path(path).applying(transform) }
        func point(_ p: CGPoint) -> CGPoint { p.applying(transform) }
        func color(_ base: NSColor, _ alpha: Double) -> Color { Color(nsColor: base).opacity(alpha) }
        switch mark {
        case .ring(let alpha):
            context.stroke(path(StatusRing.ring), with: .color(color(ring, alpha)), lineWidth: width)
        case .arc(let fraction, let alpha):
            // A closed arc is the whole ring, with no seam at the top.
            let arc = fraction >= 0.9999 ? StatusRing.ring : StatusRing.arc(from: 0, to: max(0.012, fraction * 2 * .pi))
            context.stroke(path(arc), with: .color(color(ring, alpha)), style: round)
        case .head(let fraction, let alpha):
            let end = max(0.012, fraction * 2 * .pi), span = min(end, 2 * .pi / 3), start = end - span
            if span < 0.05 {
                // Too short to shade: a dot where the arc begins.
                let top = point(StatusRing.point(at: 0)), r = width / 2
                context.fill(Path(ellipseIn: CGRect(x: top.x - r, y: top.y - r, width: 2 * r, height: 2 * r)), with: .color(color(ring, alpha)))
                return
            }
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(stops: [.init(color: color(ring, 0), location: 0), .init(color: color(ring, alpha), location: 1)]),
                startPoint: point(StatusRing.point(at: start)), endPoint: point(StatusRing.point(at: end)))
            context.stroke(path(StatusRing.arc(from: start, to: end)), with: shading, style: round)
        case .light(let angle, let alpha):
            let half = Double.pi / 3, soft = 0.22 * alpha
            let stops: [Gradient.Stop] = [(0, 0), (0.3, soft), (0.5, alpha), (0.7, soft), (1, 0)].map {
                .init(color: color(ring, $0.1), location: $0.0)
            }
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(stops: stops), startPoint: point(StatusRing.point(at: angle - half)), endPoint: point(StatusRing.point(at: angle + half)))
            context.stroke(path(StatusRing.arc(from: angle - half, to: angle + half)), with: shading, lineWidth: width)
        case .check(let reveal):
            draw(reveal, alongX: true, range: StatusRing.checkReveal, in: &context, scale: scale) { layer in
                layer.stroke(path(StatusRing.check), with: .color(color(ink, Constants.statusRingDone)), style: round)
            }
        case .exclamation(let reveal):
            draw(reveal, alongX: false, range: StatusRing.exclamationReveal, in: &context, scale: scale) { layer in
                layer.stroke(path(StatusRing.exclamationStroke), with: .color(color(akane, Constants.statusRingDone)), style: round)
                layer.fill(path(StatusRing.exclamationDotPath), with: .color(color(akane, Constants.statusRingDone)))
            }
        }
    }

    // A reveal: a wipe across x or down y through `range`, behind a soft edge, clearing from a
    // slight blur; a plain fade under Reduce Motion.
    private static func draw(_ reveal: StatusRingFrame.Reveal, alongX: Bool, range: ClosedRange<Double>,
                             in context: inout GraphicsContext, scale: Double, content: (inout GraphicsContext) -> Void) {
        let p = reveal.progress
        guard p > 0.002 else { return }
        var layer = context
        guard reveal.wipes, p < 0.998 else {
            layer.opacity = p >= 0.997 ? 1 : p
            layer.drawLayer { content(&$0) }
            return
        }
        let soft = Constants.statusRingRevealEdge
        let edge = range.lowerBound - soft + (range.upperBound - range.lowerBound + 2 * soft) * p
        layer.opacity = min(1, p * 1.4)
        let blur = Constants.statusRingRevealBlur * (1 - p)
        if blur > 0.02 { layer.addFilter(.blur(radius: blur * scale)) }
        layer.drawLayer { wiped in
            content(&wiped)
            // Keeps what lies before the edge, fading out across its last `soft` points.
            wiped.blendMode = .destinationIn
            let from = alongX ? CGPoint(x: (edge - soft) * scale, y: 0) : CGPoint(x: 0, y: (edge - soft) * scale)
            let to = alongX ? CGPoint(x: edge * scale, y: 0) : CGPoint(x: 0, y: edge * scale)
            wiped.fill(Path(CGRect(x: -2 * scale, y: -2 * scale, width: 18 * scale, height: 18 * scale)),
                       with: .linearGradient(Gradient(colors: [.white, .white.opacity(0)]), startPoint: from, endPoint: to))
        }
    }
}

/// The status ring at one frame, `size` points square, in the floating UI's ink and akane for
/// the appearance, or in `ink` when given one (Settings draws it in its label's colour).
struct StatusRingGlyph: View {
    let frame: StatusRingFrame
    var size: Double = StatusRing.grid
    var ink: NSColor?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let ink = ink ?? Palette.HUD.for(colorScheme).text
        let akane = colorScheme == .dark ? Palette.akaneOnDark : Palette.akane
        Canvas { context, canvasSize in
            StatusRingRenderer.draw(frame, in: &context, size: canvasSize, ink: ink, akane: akane)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
