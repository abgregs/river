import CoreGraphics
import Foundation

/// River's mark (docs/design/kawa-identity.md): 川, kawa, three brush strokes, drawn by a brush
/// model and traced as cubic Béziers by the study's generator (docs/design/studies/kawa/). One
/// set of shapes that every surface draws, the panel, the menu bar glyph and the app icon, so
/// they match by construction.
///
/// Shapes are in design units with y pointing down, on a 1000-unit square. The outlines, the
/// spines, the box and the centring point are generated into `KawaMark+Outlines.swift`.
enum KawaMark {
    typealias Point = SIMD2<Double>

    static let strokeCount = 3

    /// The brush spines, top to tip, one per stroke.
    static let spines: [[Point]] = spineData.map { values in
        stride(from: 0, to: values.count, by: 2).map { Point(values[$0], values[$0 + 1]) }
    }

    /// Places the mark `height` tall with its centring point (`centre`, halfway between the
    /// box's centre and the ink's centroid) at `point`.
    /// **Why:** centring the box put the tall right strokes visibly right of centre, because the
    /// left stroke's swoop widens the box; centring the ink overcorrected (maintainer,
    /// 2026-10-29, "halfway" on both axes).
    static func transform(height: Double, centredAt point: CGPoint) -> CGAffineTransform {
        let scale = height / box.height
        return CGAffineTransform(translationX: point.x - centre.x * scale, y: point.y - centre.y * scale)
            .scaledBy(x: scale, y: scale)
    }

    /// Stroke `index`'s outline.
    static func path(_ index: Int, transform: CGAffineTransform) -> CGPath {
        let values = outlineData[index]
        let path = CGMutablePath()
        path.move(to: CGPoint(x: values[0], y: values[1]), transform: transform)
        for i in stride(from: 2, to: values.count, by: 6) {
            path.addCurve(to: CGPoint(x: values[i + 4], y: values[i + 5]),
                          control1: CGPoint(x: values[i], y: values[i + 1]),
                          control2: CGPoint(x: values[i + 2], y: values[i + 3]),
                          transform: transform)
        }
        path.closeSubpath()
        return path
    }

    /// The whole mark.
    static func path(transform: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        for index in 0..<strokeCount { path.addPath(self.path(index, transform: transform)) }
        return path
    }

    /// The point `u` of the way along stroke `index`'s spine by length, 0 at the top.
    static func pointAlong(stroke index: Int, u: Double) -> Point {
        let spine = spines[index]
        var lengths = [0.0]
        for i in 1..<spine.count { lengths.append(lengths[i - 1] + ((spine[i] - spine[i - 1]) * (spine[i] - spine[i - 1])).sum().squareRoot()) }
        let want = min(1, max(0, u)) * lengths.last!
        for i in 1..<spine.count where lengths[i] >= want {
            let span = lengths[i] - lengths[i - 1]
            let f = span > 0 ? (want - lengths[i - 1]) / span : 0
            return spine[i - 1] + (spine[i] - spine[i - 1]) * f
        }
        return spine.last!
    }
}
