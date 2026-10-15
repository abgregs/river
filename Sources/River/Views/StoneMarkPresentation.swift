import Foundation

/// What the mark is doing. Preparing is the idle mark while the model gets ready at launch:
/// the r held still.
enum MarkActivity: Equatable {
    case rest, listening, transcribing, preparing

    static func of(state: RiverState, isModelPreparing: Bool) -> MarkActivity {
        switch state {
        case .recording: return .listening
        case .processing: return .transcribing
        case .idle: return isModelPreparing ? .preparing : .rest
        }
    }
}

/// Pure functions behind the stones mark, ported number for number from the study page
/// (docs/design/studies/stones-motion.html), so the view only draws and every value that
/// shapes the motion is unit-tested.
enum StoneMarkPresentation {
    // Exponential approach per frame; frame-rate independent, and a retarget mid-way
    // continues from wherever the value is.
    static func follow(current: Double, target: Double, rate: Double, interval: Double) -> Double {
        current + (target - current) * (1 - exp(-rate * interval))
    }

    // Frames after a pause (the timeline stops at idle) must not leap ahead.
    static func frameInterval(from previous: Double?, to now: Double) -> Double {
        guard let previous else { return 0 }
        return min(Constants.markMaxFrameInterval, max(0, now - previous))
    }

    // A critically damped spring, solved exactly over the interval rather than stepped, so the
    // morph is the same at 60 or 120 frames a second. A retarget mid-way keeps the velocity,
    // so an interrupted morph turns around without a jump. A spring only ever approaches its
    // goal, so within a ten-thousandth it lands: a settled mark is still, not drifting.
    static func spring(position: Double, velocity: Double, goal: Double, interval: Double) -> (position: Double, velocity: Double) {
        let omega = 2 * Double.pi / Constants.markMorphResponse
        let offset = position - goal
        let slope = velocity + omega * offset
        let decay = exp(-omega * interval)
        let next = (position: goal + (offset + slope * interval) * decay,
                    velocity: (slope - omega * (offset + slope * interval)) * decay)
        return abs(next.position - goal) < 1e-4 && abs(next.velocity) < 1e-3 ? (goal, 0) : next
    }

    // A bar reaches the voice's level only as its stone lands, and leaves it as the morph back
    // starts: the height is the level times progress to the fourth. Without it the foot, growing
    // into a tall bar, rose into the hook's underside mid-morph whenever the level was above
    // about 0.2 (25–67 ms of overlap, measured on the study page 2026-10-14); with it every
    // level keeps the clearance of silence.
    static func morphLevel(_ level: Double, progress: Double) -> Double {
        let t = min(1, max(0, progress))
        return level * t * t * t * t
    }

    // Loudness in decibels between the silence floor and the full-bar ceiling, the way a level
    // meter reads. Display only: it reads `inputLevel`, which nothing on the capture path uses.
    static func loudness(level: Double) -> Double {
        let rms = level * Double(Constants.inputLevelReferenceRMS)
        guard rms > 0 else { return 0 }
        let floor = Constants.markMeterFloorDecibels, ceiling = Constants.markMeterCeilingDecibels
        return min(1, max(0, (20 * log10(rms) - floor) / (ceiling - floor)))
    }

    // Reduce Motion swaps the r and the bars at the bottom of a quick dip instead of morphing.
    static func fadeThroughOpacity(since: Double) -> Double {
        let progress = since / Constants.markFadeThroughSeconds
        guard progress >= 0, progress < 1 else { return 1 }
        return abs(1 - 2 * progress)
    }
}

/// The mark between display frames: each stone's progress toward its bar, the three bars'
/// levels, and the recent level. A value advanced once per frame by `advanced`.
struct StoneMarkFrame: Equatable {
    /// One stone's morph: 0 is the stone, 1 its bar. It heads for `goal` from `start` on, and
    /// for `earlierGoal` before then, which is how the stagger and the opening hold work.
    struct Piece: Equatable {
        var progress = 0.0
        var velocity = 0.0
        var goal = 0.0
        var earlierGoal = 0.0
        var start = 0.0

        func goal(at time: Double) -> Double { time >= start ? goal : earlierGoal }
    }

    /// One bar's reading, 0 at silence and 1 at the ceiling.
    struct Bar: Equatable {
        var level = 0.0
        var target = 0.0
        var nextSample = 0.0
    }

    private(set) var activity: MarkActivity = .rest
    private(set) var time: Double?
    private(set) var pieces = Array(repeating: Piece(), count: 3)
    private(set) var bars = Array(repeating: Bar(), count: 3)
    private(set) var smoothedLevel = 0.0
    private(set) var fadeStart: Double?
    private(set) var reduceMotion = false
    private var random: SplitMix64

    // The r at rest; the seed makes the bars' randomness repeatable in tests.
    init(seed: UInt64 = .random(in: .min ... .max)) {
        random = SplitMix64(seed: seed)
    }

    /// Stone `index`'s progress toward its bar, 0…1.
    func progress(ofPiece index: Int) -> Double {
        min(1, max(0, pieces[index].progress))
    }

    /// The level bar `index` is drawn at.
    func displayedLevel(ofBar index: Int) -> Double {
        reduceMotion ? bars[index].level : StoneMarkPresentation.morphLevel(bars[index].level, progress: progress(ofPiece: index))
    }

    /// Stone `index` as drawn this frame.
    func outline(ofPiece index: Int) -> [StoneMark.Point] {
        StoneMark.blend(StoneMark.pieces[index], StoneMark.bar(index, level: displayedLevel(ofBar: index)),
                        progress: progress(ofPiece: index))
    }

    /// The whole mark's sideways slide in design units: centered as the r, centered as bars.
    var centering: Double {
        let progress = (0..<pieces.count).map { self.progress(ofPiece: $0) }.reduce(0, +) / Double(pieces.count)
        return StoneMark.restCentering * (1 - progress)
    }

    var opacity: Double {
        guard let fadeStart, let time else { return 1 }
        return StoneMarkPresentation.fadeThroughOpacity(since: time - fadeStart)
    }

    func advanced(to now: Double, activity newActivity: MarkActivity, inputLevel: Double, reduceMotion newReduceMotion: Bool) -> StoneMarkFrame {
        typealias Mark = StoneMarkPresentation
        var next = self
        let interval = Mark.frameInterval(from: time, to: now)
        next.time = now
        next.reduceMotion = newReduceMotion
        if newActivity != activity { next.enter(newActivity, at: now) }
        let level = newActivity == .listening ? Mark.loudness(level: min(1, max(0, inputLevel))) : 0
        next.smoothedLevel = Mark.follow(current: smoothedLevel, target: level,
                                         rate: level > smoothedLevel ? Constants.markLevelAttackRate : Constants.markLevelReleaseRate,
                                         interval: interval)
        next.read(level, at: now, interval: interval)
        for index in next.pieces.indices {
            let goal = next.pieces[index].goal(at: now)
            if newReduceMotion {
                // No travel: the swap lands at the bottom of the dip.
                let swapped = next.fadeStart.map { now >= $0 + Constants.markFadeThroughSeconds / 2 } ?? true
                if swapped { next.pieces[index].progress = goal }
                next.pieces[index].velocity = 0
            } else {
                let step = Mark.spring(position: next.pieces[index].progress, velocity: next.pieces[index].velocity,
                                       goal: goal, interval: interval)
                next.pieces[index].progress = step.position
                next.pieces[index].velocity = step.velocity
            }
        }
        return next
    }

    // Listening holds the r, then the stones leave left to right; anything else sends them back
    // right to left at once, so the exit retraces the entrance.
    private mutating func enter(_ newActivity: MarkActivity, at now: Double) {
        activity = newActivity
        let listening = newActivity == .listening
        let goal = listening ? 1.0 : 0.0
        for index in pieces.indices {
            let order = Double(listening ? index : pieces.count - 1 - index)
            let delay = (listening ? Constants.markHoldSeconds : 0) + order * Constants.markStaggerSeconds
            pieces[index].earlierGoal = pieces[index].goal(at: now)
            pieces[index].goal = goal
            pieces[index].start = now + (reduceMotion ? (listening ? Constants.markHoldSeconds : 0) : delay)
        }
        fadeStart = reduceMotion && pieces.contains { $0.earlierGoal != goal } ? now + (listening ? Constants.markHoldSeconds : 0) : nil
        if listening {
            // Random first samples, so the bars wake one by one instead of on the same frame.
            for index in bars.indices {
                bars[index] = Bar(nextSample: now + random.nextUnit() * Constants.markBarSampleInterval.lowerBound)
            }
        }
    }

    // Each bar is its own readout: it samples the voice on its own clock, at its own gain and a
    // random spread, so the three move out of step yet all rise with the voice. Below the meter's
    // floor every reading is zero, so in a pause the bars settle at rest height and hold still.
    private mutating func read(_ level: Double, at now: Double, interval: Double) {
        for index in bars.indices {
            if reduceMotion {
                bars[index].level = smoothedLevel * Constants.markBarGains[index]
                continue
            }
            if activity == .listening, now >= bars[index].nextSample {
                let spread = Constants.markBarSpread
                bars[index].target = level * Constants.markBarGains[index]
                    * (spread.lowerBound + (spread.upperBound - spread.lowerBound) * random.nextUnit())
                let sample = Constants.markBarSampleInterval
                bars[index].nextSample = now + sample.lowerBound + (sample.upperBound - sample.lowerBound) * random.nextUnit()
            } else if activity != .listening {
                bars[index].target = 0
            }
            let rising = bars[index].target > bars[index].level
            bars[index].level = min(1, StoneMarkPresentation.follow(
                current: bars[index].level, target: bars[index].target,
                rate: rising ? Constants.markBarRiseRate : Constants.markBarFallRate, interval: interval))
        }
    }
}

/// A small seedable generator, so the bars' randomness is repeatable under test.
struct SplitMix64: RandomNumberGenerator, Equatable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    // Uniform in [0, 1).
    mutating func nextUnit() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }
}
