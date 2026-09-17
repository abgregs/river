import Foundation

/// One strand of the river mark (planning 0028): its rest line in mark points, the
/// shape of its meander and ripple, and its own ink and stroke width.
struct RiverStrand: Equatable {
    let baseY: Double
    let amplitude: Double
    let meanderLength: Double
    let rippleLength: Double
    let phase: Double
    let speed: Double
    let width: Double
    let ink: Double
}
