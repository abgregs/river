import Foundation

/// Pure functions behind the pixel mark (planning 0029), ported number for number from
/// the study page so the view only draws and every value that shapes the motion is
/// unit-tested.
enum PixelMarkPresentation {
    // Strong ease-out: most of the travel happens at once, then the pixel settles, so the
    // drop answers the key press instead of trailing it.
    static func easeOut(_ progress: Double) -> Double {
        guard progress > 0 else { return 0 }
        guard progress < 1 else { return 1 }
        let curve = Constants.pixelEaseOut
        func bezier(_ u: Double, _ first: Double, _ second: Double) -> Double {
            let v = 1 - u
            return 3 * v * v * u * first + 3 * v * u * u * second + u * u * u
        }
        var low = 0.0, high = 1.0, u = progress
        for _ in 0..<24 {
            if bezier(u, curve.x1, curve.x2) < progress { low = u } else { high = u }
            u = (low + high) / 2
        }
        return bezier(u, curve.y1, curve.y2)
    }

    // Exponential approach per frame; frame-rate independent, and a retarget mid-way
    // continues from wherever the value is.
    static func follow(current: Double, target: Double, rate: Double, interval: Double) -> Double {
        current + (target - current) * (1 - exp(-rate * interval))
    }

    // Frames after a pause (the timeline stops at idle) must not leap ahead.
    static func frameInterval(from previous: Double?, to now: Double) -> Double {
        guard let previous else { return 0 }
        return min(Constants.pixelMaxFrameInterval, max(0, now - previous))
    }

    // A raised-cosine window: smooth to the first derivative, so the brightness ramp has
    // no corner that reads as an edge (working rule 14).
    static func crest(at fraction: Double, position: Double) -> Double {
        let halfWidth = Constants.pixelCrestHalfWidth
        let distance = abs(fraction - (position - halfWidth))
        return distance >= halfWidth ? 0 : 0.5 + 0.5 * cos(.pi * distance / halfWidth)
    }

    // One pass enters fully off the stem's foot and leaves fully past the tip, then rests
    // briefly, so the loop never pops.
    static var crestSpan: Double { 1 + 2 * Constants.pixelCrestHalfWidth + Constants.pixelCrestRest }

    static func crestLoop(at fraction: Double, since: Double) -> Double {
        guard since >= 0 else { return 0 }
        let position = (since / Constants.pixelCrestPeriod * crestSpan).truncatingRemainder(dividingBy: crestSpan)
        return crest(at: fraction, position: position)
    }

    // Lit rows of one meter column, fractional at the top. Silence rests at the pilot.
    static func barHeight(loudness: Double, gain: Double, factor: Double) -> Double {
        let pilot = Constants.pixelMeterPilot
        let reach = min(1, max(0, loudness * gain * factor))
        return pilot + (Double(PixelMark.meterRows) - pilot) * reach
    }

    // Loudness in decibels between a silence floor and a full-column ceiling, the way a
    // level meter reads: linear, a whisper filled a sliver of the bottom row. Display only:
    // it reads `inputLevel`, which nothing on the capture path uses.
    static func loudness(level: Double) -> Double {
        let rms = level * Double(Constants.inputLevelReferenceRMS)
        guard rms > 0 else { return 0 }
        let floor = Constants.pixelMeterFloorDecibels, ceiling = Constants.pixelMeterCeilingDecibels
        return min(1, max(0, (20 * log10(rms) - floor) / (ceiling - floor)))
    }

    // Reduce Motion swaps layouts at the bottom of a quick dip instead of moving pixels.
    static func fadeThroughOpacity(since: Double) -> Double {
        let progress = since / Constants.pixelFadeThroughSeconds
        guard progress >= 0, progress < 1 else { return 1 }
        return abs(1 - 2 * progress)
    }

    // Increase Contrast lifts the dim cells so the silhouette never drops out.
    static func displayInk(_ ink: Double, increaseContrast: Bool) -> Double {
        increaseContrast ? max(ink, Constants.pixelIncreasedContrastInkFloor) : ink
    }
}

/// The mark between display frames: where each pixel is travelling, its ink, the four
/// meter columns, and the recent level. A value advanced once per frame by `advanced`.
struct PixelMarkFrame: Equatable {
    struct Travel: Equatable {
        var fromX = 0.0, fromY = 0.0, toX = 0.0, toY = 0.0, start = 0.0, duration = 0.0

        func offset(at time: Double) -> (x: Double, y: Double) {
            let progress = PixelMarkPresentation.easeOut((time - start) / max(duration, 1e-6))
            return (fromX + (toX - fromX) * progress, fromY + (toY - fromY) * progress)
        }

        // Retargets from the current position, so an interrupted move never jumps.
        mutating func retarget(at now: Double, toX: Double, toY: Double, delay: Double, duration: Double) {
            let current = offset(at: now)
            self = Travel(fromX: current.x, fromY: current.y, toX: toX, toY: toY, start: now + delay, duration: duration)
        }
    }

    struct Bar: Equatable {
        var height: Double
        var target: Double
        var nextTick: Double
    }

    struct Heard: Equatable {
        let time: Double
        let level: Double
    }

    private(set) var state: RiverState = .idle
    private(set) var time: Double?
    private(set) var travel: [Travel]
    private(set) var accentMix: [Double]
    private(set) var ink: [Double]
    private(set) var bars: [Bar]
    private(set) var heard: [Heard] = []
    private(set) var smoothedLevel = 0.0
    private(set) var crestStart = 0.0
    private(set) var fadeStart: Double?
    private var random: SplitMix64

    // The r at rest; the seed makes the meter's randomness repeatable in tests.
    init(seed: UInt64 = .random(in: .min ... .max)) {
        let count = PixelMark.cells.count
        travel = Array(repeating: Travel(), count: count)
        accentMix = Array(repeating: 0, count: count)
        ink = Array(repeating: 1, count: count)
        bars = Array(repeating: Bar(height: Constants.pixelMeterPilot, target: Constants.pixelMeterPilot, nextTick: 0),
                     count: PixelMark.meterColumns)
        random = SplitMix64(seed: seed)
    }

    func offset(ofCell index: Int) -> (x: Double, y: Double) {
        travel[index].offset(at: time ?? 0)
    }

    var opacity: Double {
        guard let fadeStart, let time else { return 1 }
        return PixelMarkPresentation.fadeThroughOpacity(since: time - fadeStart)
    }

    func advanced(to now: Double, state newState: RiverState, inputLevel: Double, reduceMotion: Bool) -> PixelMarkFrame {
        typealias Mark = PixelMarkPresentation
        var next = self
        let interval = Mark.frameInterval(from: time, to: now)
        next.time = now
        if newState != state { next.enter(newState, at: now, reduceMotion: reduceMotion) }
        let level = newState == .recording ? min(1, max(0, inputLevel)) : 0
        next.smoothedLevel = Mark.follow(current: smoothedLevel, target: level,
                                         rate: level > smoothedLevel ? Constants.pixelLevelAttackRate : Constants.pixelLevelReleaseRate,
                                         interval: interval)
        if newState == .recording { next.listen(level, at: now, interval: interval, reduceMotion: reduceMotion) }
        for (index, cell) in PixelMark.cells.enumerated() {
            let target = next.inkTarget(for: cell, at: now, reduceMotion: reduceMotion)
            next.accentMix[index] = Mark.follow(current: accentMix[index], target: target.accentMix,
                                                rate: Constants.pixelInkRate, interval: interval)
            next.ink[index] = Mark.follow(current: ink[index], target: target.ink,
                                          rate: Constants.pixelInkRate, interval: interval)
        }
        return next
    }

    private mutating func enter(_ newState: RiverState, at now: Double, reduceMotion: Bool) {
        state = newState
        let toMeter = newState == .recording
        if toMeter {
            heard.removeAll()
            // Random first ticks, so the columns wake one by one instead of on the same frame.
            for index in bars.indices {
                bars[index] = Bar(height: Constants.pixelMeterPilot, target: Constants.pixelMeterPilot,
                                  nextTick: now + random.nextUnit() * Constants.pixelMeterTickRange.lowerBound)
            }
        }
        for (index, cell) in PixelMark.cells.enumerated() {
            let toX = toMeter ? Double(cell.meterX - cell.x) : 0
            let toY = toMeter ? Double(cell.meterY - cell.y) : 0
            if reduceMotion {
                travel[index].retarget(at: now, toX: toX, toY: toY, delay: Constants.pixelFadeThroughSeconds / 2, duration: 0)
            } else {
                // All sixteen together: staggering them sends pixels through each other mid-flight.
                travel[index].retarget(at: now, toX: toX, toY: toY, delay: 0,
                                       duration: toMeter ? Constants.pixelDropSeconds : Constants.pixelReturnSeconds)
            }
        }
        if reduceMotion {
            fadeStart = now
            crestStart = now
        } else {
            fadeStart = nil
            // The crest writes the stroke once the r is whole again.
            crestStart = now + Constants.pixelReturnSeconds
        }
    }

    // Each column is its own readout: it hears the voice a little late, in shuffled order,
    // samples it on its own clock, and picks a height within the range the loudness allows,
    // so the four move out of step yet all rise with the voice and settle in silence.
    private mutating func listen(_ level: Double, at now: Double, interval: Double, reduceMotion: Bool) {
        typealias Mark = PixelMarkPresentation
        heard.append(Heard(time: now, level: level))
        heard.removeAll { $0.time < now - Constants.pixelMeterHistorySeconds }
        for index in bars.indices {
            let gain = Constants.pixelMeterGains[index]
            if reduceMotion {
                bars[index].height = Mark.barHeight(loudness: Mark.loudness(level: smoothedLevel), gain: gain, factor: 1)
                continue
            }
            if now >= bars[index].nextTick {
                let delay = Constants.pixelMeterHearDelays[index]
                let heardLevel = heard.last { $0.time <= now - delay }?.level ?? 0
                let factor = Constants.pixelMeterSpreadFloor + random.nextUnit()
                bars[index].target = Mark.barHeight(loudness: Mark.loudness(level: heardLevel), gain: gain, factor: factor)
                let ticks = Constants.pixelMeterTickRange
                bars[index].nextTick = now + ticks.lowerBound + (ticks.upperBound - ticks.lowerBound) * random.nextUnit()
            }
            let rising = bars[index].target > bars[index].height
            bars[index].height = Mark.follow(current: bars[index].height, target: bars[index].target,
                                             rate: rising ? Constants.pixelBarAttackRate : Constants.pixelBarReleaseRate,
                                             interval: interval)
        }
    }

    private func inkTarget(for cell: PixelMark.Cell, at now: Double, reduceMotion: Bool) -> (accentMix: Double, ink: Double) {
        switch state {
        case .recording:
            let lit = min(1, max(0, bars[cell.meterColumn].height - Double(cell.meterStack)))
            return (lit, Constants.pixelUnlitInk + (Constants.pixelLitInk - Constants.pixelUnlitInk) * lit)
        case .processing:
            if reduceMotion { return (0, PixelMark.ditherInk(cell)) }
            let crest = PixelMarkPresentation.crestLoop(at: cell.strokeFraction, since: now - crestStart)
            return (0, Constants.pixelCrestBase + (1 - Constants.pixelCrestBase) * crest)
        case .idle:
            return (0, 1)
        }
    }
}

/// A small seedable generator, so the meter's randomness is repeatable under test.
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
