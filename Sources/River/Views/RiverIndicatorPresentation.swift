import CoreGraphics
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

/// Pure functions behind the river indicator (planning 0028), ported number for
/// number from the study page's river block so the view only draws and every value
/// that shapes the motion is unit-tested.
enum RiverIndicatorPresentation {
    // The level the strands chase: rest at idle, the live input while recording, a
    // held level while transcribing.
    static func targetLevel(state: RiverState, inputLevel: Double) -> Double {
        switch state {
        case .idle: return 0
        case .recording: return min(max(inputLevel, 0), 1)
        case .processing: return Constants.riverTranscribingLevel
        }
    }

    // Exponential approach per frame: faster attack than release, so the water wakes
    // quickly and settles slowly. The rate times dt is capped so a long frame lands, not overshoots.
    static func smoothedLevel(current: Double, target: Double, frameInterval: Double) -> Double {
        let rate = target > current ? Constants.riverAttackRate : Constants.riverReleaseRate
        return current + (target - current) * min(1, rate * frameInterval)
    }

    // Amplitude and width never fall below the rest shape, which keeps every strand out
    // of the sub-pixel band that read as grain (identity-studies working rule 11).
    static func motion(level: Double) -> Double {
        max(level, Constants.riverRestLevel)
    }

    // How far the ink and speed have woken: a smoothstep over the first half of the range.
    static func inkProgress(level: Double) -> Double {
        let x = min(1, max(0, level / Constants.riverInkSpan))
        return x * x * (3 - 2 * x)
    }

    // The strand clock slows toward rest instead of stopping.
    static func clockRate(level: Double) -> Double {
        Constants.riverRestSpeed + (1 - Constants.riverRestSpeed) * inkProgress(level: level)
    }

    // Ink at rest with its slow breath; the breath holds still under Reduce Motion.
    static func restInk(time: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return Constants.riverRestInk }
        return Constants.riverRestInk + Constants.riverBreathDepth * sin(Constants.riverBreathRate * time)
    }

    static func strandOpacity(_ strand: RiverStrand, level: Double, time: Double, reduceMotion: Bool) -> Double {
        let rest = restInk(time: time, reduceMotion: reduceMotion)
        return rest + (strand.ink - rest) * inkProgress(level: level)
    }

    static func strandWidth(_ strand: RiverStrand, level: Double) -> Double {
        strand.width + Constants.riverWidthGain * motion(level: level)
    }

    // The strand's y at fraction `u` across the mark; `clock` is the strand clock.
    static func strandY(_ strand: RiverStrand, fraction u: Double, motion: Double, clock: Double) -> Double {
        let amplitude = Constants.riverAmplitudeScale * motion * strand.amplitude
        let meander = sin(2 * .pi * u / strand.meanderLength + strand.phase
            + Constants.riverMeanderDrift * strand.speed * clock)
        let ripple = Constants.riverRippleWeight * sin(2 * .pi * u / strand.rippleLength
            - Constants.riverRippleDrift * strand.speed * clock + Constants.riverRipplePhaseGain * strand.phase)
        return strand.baseY + amplitude * (meander + ripple)
    }

    static func strandPoints(_ strand: RiverStrand, motion: Double, clock: Double) -> [CGPoint] {
        let steps = Constants.riverSampleCount - 1
        return (0...steps).map { index in
            let u = Double(index) / Double(steps)
            return CGPoint(x: u * Constants.riverMarkWidth,
                           y: strandY(strand, fraction: u, motion: motion, clock: clock))
        }
    }

    // Under Reduce Motion transcribing is the calm lines at full ink: no crest.
    static func crestBlendTarget(state: RiverState, reduceMotion: Bool) -> Double {
        state == .processing && !reduceMotion ? 1 : 0
    }

    static func crestBlend(current: Double, target: Double, frameInterval: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return target }
        return current + (target - current) * min(1, Constants.riverCrestBlendRate * frameInterval)
    }

    // The stroke's base ink under the crest: full while listening, dimmed while transcribing.
    static func crestBase(blend: Double) -> Double {
        1 - (1 - Constants.riverCrestBase) * blend
    }

    // A raised-cosine window sampled at every stop: smooth to the first derivative, so no
    // corner in the brightness ramp reads as an edge (working rule 14).
    static func crestStopOpacities(base: Double) -> [Double] {
        let last = Double(Constants.riverCrestStopCount - 1)
        return (0..<Constants.riverCrestStopCount).map { stop in
            let window = 0.5 - 0.5 * cos(2 * .pi * Double(stop) / last)
            return base + (1 - base) * window
        }
    }

    // The window's left edge in mark x: it enters from fully left of the mark and exits
    // fully right once per period, each strand offset by a fraction of the period.
    static func crestOffset(time: Double, strandIndex: Int) -> Double {
        let cycle = time / Constants.riverCrestPeriod + Double(strandIndex) * Constants.riverCrestStagger
        let phase = cycle - floor(cycle)
        let travel = Constants.riverMarkWidth + 2 * Constants.riverCrestWidth
        return -Constants.riverCrestWidth + phase * travel
    }

    // Frames after a pause (the timeline stops at idle) must not leap the clock ahead.
    static func frameInterval(from previous: Double?, to now: Double) -> Double {
        guard let previous else { return 0 }
        return min(Constants.riverMaxFrameInterval, max(0, now - previous))
    }
}

/// The engine's state between display frames: the smoothed level, the strand clock,
/// and the crest blend. A value advanced once per frame by `advanced`.
struct RiverIndicatorFrame: Equatable {
    var level: Double = 0
    var clock: Double = 0
    var crestBlend: Double = 0
    var time: Double?

    func advanced(to now: Double, state: RiverState, inputLevel: Double, reduceMotion: Bool) -> RiverIndicatorFrame {
        let interval = RiverIndicatorPresentation.frameInterval(from: time, to: now)
        var next = self
        next.level = RiverIndicatorPresentation.smoothedLevel(
            current: level,
            target: RiverIndicatorPresentation.targetLevel(state: state, inputLevel: inputLevel),
            frameInterval: interval)
        next.clock += interval * RiverIndicatorPresentation.clockRate(level: next.level)
        next.crestBlend = RiverIndicatorPresentation.crestBlend(
            current: crestBlend,
            target: RiverIndicatorPresentation.crestBlendTarget(state: state, reduceMotion: reduceMotion),
            frameInterval: interval,
            reduceMotion: reduceMotion)
        next.time = now
        return next
    }
}
