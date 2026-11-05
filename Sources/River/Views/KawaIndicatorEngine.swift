import CoreGraphics
import Foundation
import OSLog

/// The voice behind the kawa indicator, ported from the study's `step()` (docs/design/studies/
/// kawa/kawa-studies-r1.html): one shared smoothed level and the drops Glass ripples. It steps at
/// a fixed rate on the cycle's clock, catching up to each frame, so it reads the same at 60 or
/// 120 frames a second and a test can run it frame-free.
struct KawaIndicatorEngine {
    /// A Glass drop, in panel points (the panel's top left is the origin).
    struct Drop: Equatable {
        var x: Double
        var y: Double
        var time: Double
        /// 0, 1 or 2: soft, normal or raised.
        var tier: Int
        /// The loudest level since the previous drop, which picked `tier`.
        var peak: Double

        /// How strong the drop's ring is: its light and its bend.
        var strength: Double { Constants.kawaGlassRingStrengths[tier] }
        /// How far the drop clears the frost, in points.
        var windowRadius: Double { Constants.kawaGlassWindowRadii[tier] }
    }

    /// The shared smoothed level, 0…1.
    private(set) var level = 0.0
    /// How far the level clears the frost under Reduce Motion: the level while the voice is on,
    /// held from release, so the frost never returns before it lifts.
    private(set) var clearing = 0.0
    /// Drops whose ripple or window may still show, oldest first.
    private(set) var drops: [Drop] = []

    private var nextStep = 0
    private var since = 0.0
    private var lastDrop = -Double.infinity
    private var dropCount = 0
    // Offsets the drop sequence, so each recording's drops fall in a new order. 0 is the study's.
    private let seed: Int

    init(seed: Int = .random(in: 0..<1 << 20)) {
        self.seed = seed
    }

    /// Steps the engine up to `time`, holding the voice at `loudness` (0…1, see `loudness(level:)`).
    mutating func advance(to time: Double, loudness: Double, events: KawaIndicatorEvents, reduceMotion: Bool) {
        let rate = Constants.kawaEngineStepsPerSecond
        while Double(nextStep) / rate <= time {
            let t = Double(nextStep) / rate
            step(at: t, interval: 1 / rate, voice: loudness, isOn: KawaIndicatorTimeline.isOn(at: t, events: events),
                 reduceMotion: reduceMotion)
            nextStep += 1
        }
        drops.removeAll { time - $0.time >= Constants.kawaGlassDropSeconds }
    }

    private mutating func step(at t: Double, interval: Double, voice v: Double, isOn: Bool, reduceMotion: Bool) {
        let jitter = reduceMotion ? 0 : Constants.kawaLevelJitter * (Self.hash(7, Int((t / Constants.kawaLevelJitterClockSeconds).rounded(.down))) - 0.5) * v
        let target = isOn ? min(1, max(0, v + jitter)) : 0
        let settle = target > level ? Constants.kawaLevelRiseSeconds : Constants.kawaLevelFallSeconds
        level += (target - level) * (1 - exp(-interval / settle))
        if isOn { clearing = level }
        // A steady cadence while the level is above the threshold, however fast or loud the
        // speech. Each drop's tier is picked by the loudest level since the previous drop, so
        // a beat that lands between two loud syllables still reads loud.
        since = isOn ? max(since, level) : 0
        guard isOn, !reduceMotion, level > Constants.kawaGlassThreshold, t - lastDrop >= 1 / Constants.kawaGlassCadence else { return }
        drops.append(Self.drop(seed &+ dropCount, at: t, tier: Self.tier(peak: since), peak: since))
        dropCount += 1
        lastDrop = t
        since = 0
    }

    /// The tier a drop takes for the loudest level since the previous drop.
    static func tier(peak: Double) -> Int {
        peak >= Constants.kawaGlassLoudFrom ? 2 : peak >= Constants.kawaGlassNormalFrom ? 1 : 0
    }

    /// Drop `k`: on one of the strokes, somewhere along its spine away from the ends, nudged up
    /// to 0.6 pt off it so the drops do not line up.
    static func drop(_ k: Int, at time: Double, tier: Int, peak: Double) -> Drop {
        let stroke = Int(hash(11, k) * 3) % 3
        let along = 0.08 + 0.84 * hash(13, k)
        let spine = KawaMark.pointAlong(stroke: stroke, u: along)
        let point = CGPoint(x: spine.x, y: spine.y).applying(panelTransform)
        return Drop(x: point.x + (hash(17, k) - 0.5) * 1.2, y: point.y + (hash(19, k) - 0.5) * 1.2,
                    time: time, tier: tier, peak: peak)
    }

    /// The mark in panel points: `indicatorMarkHeight` tall, centred in the panel.
    static let panelTransform = KawaMark.transform(
        height: Constants.indicatorMarkHeight,
        centredAt: CGPoint(x: Constants.indicatorPanelWidth / 2, y: Constants.indicatorPanelHeight / 2))

    /// Loudness in decibels between the silence floor and the ceiling, the way a level meter
    /// reads, on `Constants.markMeterCurve`: the 0…1 level the study's voice is. Display only: it reads `inputLevel`, which
    /// nothing on the capture path uses.
    static func loudness(level: Double) -> Double {
        let rms = level * Double(Constants.inputLevelReferenceRMS)
        guard rms > 0 else { return 0 }
        let floor = Constants.markMeterFloorDecibels, ceiling = Constants.markMeterCeilingDecibels
        return pow(min(1, max(0, (20 * log10(rms) - floor) / (ceiling - floor))), Constants.markMeterCurve)
    }

    /// The study's integer hash, bit for bit: a repeatable value in 0…1 for each `(i, n)`.
    static func hash(_ i: Int, _ n: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: i &* 374_761_393 &+ n &* 668_265_263) ^ 0x5BF0_3635
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return Double(h ^ (h >> 16)) / 4_294_967_295
    }
}

/// The live panel's voice: the engine for the cycle on screen, fed the microphone's level once
/// a frame. It turns each level reading into loudness, starts a fresh engine for each new
/// cycle, advances it to the frame, and logs each ripple. The panel and the snapshot harness
/// both draw through it, so a held frame is fed the way the app feeds it. A reference so a
/// frame can advance it without invalidating the view; nothing observes it.
final class KawaIndicatorVoice {
    private static let logger = Logger(subsystem: Constants.loggingSubsystem, category: "indicator")
    private let makeEngine: () -> KawaIndicatorEngine
    private var cycleID: UUID?
    private var engine: KawaIndicatorEngine
    private var lastLoggedDrop = -Double.infinity

    // `makeEngine` is internal for testability: the harness and tests seed it.
    init(makeEngine: @escaping () -> KawaIndicatorEngine = { KawaIndicatorEngine() }) {
        self.makeEngine = makeEngine
        engine = makeEngine()
    }

    /// The engine for cycle `id` at `time` on its clock, holding the voice at `inputLevel`
    /// (`AppState.inputLevel`) since the last frame. Advancing to the same time twice changes
    /// nothing.
    func engine(for id: UUID, events: KawaIndicatorEvents, at time: Double, inputLevel: Double,
                reduceMotion: Bool) -> KawaIndicatorEngine {
        if cycleID != id {
            cycleID = id
            engine = makeEngine()
            lastLoggedDrop = -.infinity
        }
        engine.advance(to: time, loudness: KawaIndicatorEngine.loudness(level: inputLevel), events: events, reduceMotion: reduceMotion)
        // Where real speech falls on the level scale, for tuning the tiers on device.
        for drop in engine.drops where drop.time > lastLoggedDrop {
            Self.logger.debug("Glass ripple: peak \(drop.peak, format: .fixed(precision: 2)) → strength \(drop.strength, format: .fixed(precision: 2))")
            lastLoggedDrop = drop.time
        }
        return engine
    }
}
