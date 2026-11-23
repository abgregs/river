import CoreGraphics
import Foundation

/// What has happened to the model's status while its ring shows, in seconds on the ring's own
/// clock, which starts as the ring appears (planning 0004). A moment that has not happened yet
/// is `.infinity`, so every change that waits on it holds.
struct StatusRingEvents: Equatable {
    /// What the ring showed as it appeared. One that appears ready or failed shows its sign at
    /// once: Settings, opened long after the load ended, has nothing to animate.
    enum Start: Equatable { case downloading, preparing, ready, failed }

    /// One rise of the real download fraction, which the arc glides through.
    struct Step: Equatable {
        var at: Double
        var size: Double
    }

    var start: Start
    /// The download the arc shows: the fraction at `base`, then each rise in `steps`. Nil when
    /// the ring has no download to show: it appeared preparing, or failed after the download.
    var base: Double?
    var steps: [Step] = []
    /// The download closed and preparing began.
    var preparing: Double = .infinity
    var ready: Double = .infinity
    var failed: Double = .infinity

    /// A ring appearing in `phase`, the download at `fraction` (nil when River has none).
    init(appearing phase: StatusRing.Phase, fraction: Double?) {
        switch phase {
        case .downloading:
            start = .downloading
            base = min(max(fraction ?? 0, 0), 1)
        case .preparing:
            start = .preparing
            preparing = 0
        case .ready:
            start = .ready
        case .failed:
            start = .failed
            base = fraction.map { min(max($0, 0), 1) }
            failed = 0
        }
    }

    /// Where the download's fraction is heading: `base` and every step.
    var target: Double { (base ?? 0) + steps.reduce(0) { $0 + $1.size } }

    /// The events once the real fraction has reached `fraction` at `t`. Only a rise is recorded,
    /// so the arc never runs back. Steps that have settled fold into `base`, so the sum stays
    /// short through a long download.
    mutating func record(fraction: Double, at t: Double) {
        guard let base, !preparing.isFinite, !ready.isFinite, !failed.isFinite else { return }
        let target = self.target, value = min(fraction, 1)
        guard value > target else { return }
        let settled = steps.filter { t - $0.at >= Constants.statusRingSettledSeconds }
        self.base = base + settled.reduce(0) { $0 + $1.size }
        steps.removeAll { t - $0.at >= Constants.statusRingSettledSeconds }
        steps.append(Step(at: t, size: value - target))
    }
}

/// The ring through one status, from appearing until it leaves: the events it reads, on its
/// own clock.
struct StatusRingCycle: Equatable {
    /// The moment the ring's clock reads 0.
    let start: Date
    /// The model whose status the ring shows.
    let model: String
    private(set) var events: StatusRingEvents

    /// Seconds on the ring's clock at `date`.
    func time(at date: Date) -> Double { date.timeIntervalSince(start) }

    /// The cycle after River reports `phase` for `model`, the download at `fraction`, at `date`.
    /// A ring not showing yet appears in `phase`. A different model starts it again at its own
    /// fraction, so a switch never glides backward. A phase that moves on is recorded when it
    /// does; once failed the ring holds, and a phase it has passed is not shown again.
    static func next(_ cycle: StatusRingCycle?, phase: StatusRing.Phase, model: String, fraction: Double?,
                     at date: Date) -> StatusRingCycle {
        guard var cycle, cycle.model == model else {
            return StatusRingCycle(start: date, model: model, events: StatusRingEvents(appearing: phase, fraction: fraction))
        }
        let t = cycle.time(at: date)
        guard !cycle.events.failed.isFinite, !cycle.events.ready.isFinite else { return cycle }
        switch phase {
        case .downloading:
            if let fraction { cycle.events.record(fraction: fraction, at: t) }
        case .preparing:
            if !cycle.events.preparing.isFinite { cycle.events.preparing = t }
        case .ready:
            if !cycle.events.preparing.isFinite { cycle.events.preparing = t }
            cycle.events.ready = t
        case .failed:
            cycle.events.failed = t
        }
        return cycle
    }
}

/// One drawing of the ring: groups of marks, each group composited at its own opacity.
struct StatusRingFrame: Equatable {
    /// How a check or an exclamation mark comes in.
    struct Reveal: Equatable {
        /// How far it has come in, 0 to 1.
        var progress: Double
        /// A wipe behind a soft edge, clearing from a slight blur; a plain fade under Reduce Motion.
        var wipes: Bool
    }

    enum Mark: Equatable {
        /// The whole ring at `alpha`.
        case ring(alpha: Double)
        /// The arc that has arrived: from 12 o'clock to `fraction` of the way round, at `alpha`.
        case arc(fraction: Double, alpha: Double)
        /// The head: the last third of the arc to `fraction`, clear where it starts and `alpha`
        /// at its end, where the data is landing.
        case head(fraction: Double, alpha: Double)
        /// Preparing's light: a third of the ring centred `angle` radians clockwise from 12
        /// o'clock, clear at both ends and `alpha` at its middle.
        case light(angle: Double, alpha: Double)
        /// Ready's check, in the ring's ink at done strength.
        case check(Reveal)
        /// A failed load's exclamation mark, in akane at done strength.
        case exclamation(Reveal)
    }

    struct Layer: Equatable {
        var opacity: Double
        var marks: [Mark]
    }

    var layers: [Layer]
    /// How far the ring's strokes have turned akane: 0 is the ring's ink, 1 akane.
    var akane: Double
}

/// The model's status ring (planning 0004): the arc fills with the real download fraction, a
/// light turns round the ring while the model is prepared, a check is revealed when it is
/// ready, and the ring turns akane round an exclamation mark when it couldn't load. Drawn on the
/// mark's 14 pt grid beside the recording indicator, and in Settings and the menu.
/// Pure, so every moment is unit-tested; `StatusRingRenderer` draws a frame.
enum StatusRing {
    /// The model's state the ring shows.
    enum Phase: Equatable { case downloading, preparing, ready, failed }

    // MARK: Geometry, on the 14 pt grid with y pointing down

    static let grid: Double = 14
    static let center = CGPoint(x: 7, y: 7)
    static let checkPoints = [CGPoint(x: 4.65, y: 7.15), CGPoint(x: 6.35, y: 8.85), CGPoint(x: 9.45, y: 5.35)]
    /// The exclamation mark: a stroke at x 7 from `exclamationTop` to `exclamationBottom`, and a
    /// dot below it.
    static let exclamationTop: Double = 4.6
    static let exclamationBottom: Double = 7.25
    static let exclamationDot = CGPoint(x: 7, y: 9.3)
    static let exclamationDotRadius: Double = 0.68
    /// Where each reveal's wipe runs: the check from the left, the exclamation mark from the top.
    static let checkReveal: ClosedRange<Double> = 4.1...10
    static let exclamationReveal: ClosedRange<Double> = 4.05...10

    /// The point on the ring at `angle` radians clockwise from 12 o'clock.
    static func point(at angle: Double) -> CGPoint {
        let r = Constants.statusRingRadius
        return CGPoint(x: center.x + r * sin(angle), y: center.y - r * cos(angle))
    }

    /// The ring's arc from `from` to `to`, in radians clockwise from 12 o'clock.
    static func arc(from: Double, to: Double) -> CGPath {
        let path = CGMutablePath()
        path.addArc(center: center, radius: Constants.statusRingRadius,
                    startAngle: from - .pi / 2, endAngle: to - .pi / 2, clockwise: false)
        return path
    }

    static let ring: CGPath = {
        let r = Constants.statusRingRadius
        return CGPath(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r), transform: nil)
    }()

    static let check: CGPath = {
        let path = CGMutablePath()
        path.addLines(between: checkPoints)
        return path
    }()

    static let exclamationStroke: CGPath = {
        let path = CGMutablePath()
        path.addLines(between: [CGPoint(x: 7, y: exclamationTop), CGPoint(x: 7, y: exclamationBottom)])
        return path
    }()

    static let exclamationDotPath: CGPath = {
        let r = exclamationDotRadius
        return CGPath(ellipseIn: CGRect(x: exclamationDot.x - r, y: exclamationDot.y - r, width: 2 * r, height: 2 * r),
                      transform: nil)
    }()

    // MARK: Motion

    /// The arc's fraction at `t`: `base`, plus each step settled on the spring. Nil with no download.
    static func fraction(at t: Double, events ev: StatusRingEvents) -> Double? {
        guard let base = ev.base else { return nil }
        return min(1, base + ev.steps.reduce(0) { $0 + $1.size * settle(t - $1.at) })
    }

    /// How far a step `x` seconds old has come: a critically damped spring's step response,
    /// which never overshoots.
    static func settle(_ x: Double) -> Double {
        guard x > 0 else { return 0 }
        let w = Constants.statusRingGlideRate
        return 1 - (1 + w * x) * exp(-w * x)
    }

    /// The head's breath at `t`: 0, up to 1 and back over each period. None under Reduce Motion.
    static func breath(at t: Double, reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : bump(cycle(t, Constants.statusRingBreathSeconds))
    }

    /// Where preparing's light is, `tau` seconds after it set off: from rest at the top, up to a
    /// turn every `statusRingLightTurnSeconds` over `statusRingLightRampSeconds`.
    static func lightAngle(_ tau: Double) -> Double {
        let w = 2 * .pi / Constants.statusRingLightTurnSeconds, ramp = Constants.statusRingLightRampSeconds
        guard tau > 0 else { return 0 }
        return tau < ramp ? 0.5 * w * tau * tau / ramp : w * (tau - ramp / 2)
    }

    /// The alpha that, laid over `base` in the same colour, makes `target`.
    static func over(_ target: Double, _ base: Double) -> Double {
        min(1, max(0, 1 - (1 - target) / (1 - base)))
    }

    /// The ring at `t`.
    static func frame(at t: Double, events ev: StatusRingEvents, reduceMotion rm: Bool) -> StatusRingFrame {
        typealias C = Constants
        // A change from `start` over `duration`; under Reduce Motion, a linear fade.
        func tween(_ start: Double, _ duration: Double, _ curve: CubicBezier = .gentle) -> Double {
            rm ? clamp((t - start) / C.kawaReducedFadeSeconds) : curve(clamp((t - start) / duration))
        }
        func layer(_ marks: [StatusRingFrame.Mark], _ opacity: Double = 1) -> StatusRingFrame.Layer {
            StatusRingFrame.Layer(opacity: opacity, marks: marks)
        }
        // A model ready with no preparing seen was prepared the moment it was ready.
        let prepared = min(ev.preparing, ev.ready)
        let light = over(C.statusRingDone, C.statusRingUnderWay)
        // Preparing's ring, `tau` in: the turning light, or under Reduce Motion a slow pulse.
        func preparingStrength(_ tau: Double) -> Double {
            rm ? C.statusRingUnderWay + C.statusRingReducedPulse * bump(cycle(tau, C.statusRingBreathSeconds)) : C.statusRingUnderWay
        }
        func preparing(_ tau: Double) -> [StatusRingFrame.Mark] {
            rm ? [.ring(alpha: preparingStrength(tau))]
                : [.ring(alpha: C.statusRingUnderWay), .light(angle: lightAngle(tau), alpha: light)]
        }
        // The arc closing as preparing begins: what was still to come glides in, and the breath settles.
        func closing() -> [StatusRingFrame.Mark] {
            let q = min(1, (fraction(at: t, events: ev) ?? 0) + (1 - ev.target) * settle(t - prepared))
            let breath = breath(at: prepared, reduceMotion: rm) * (1 - tween(prepared, C.statusRingSettleSeconds))
            return download(q, breath: breath)
        }
        let handOff = ev.start == .downloading ? tween(prepared, C.statusRingHandOffSeconds) : 1
        let sign = StatusRingFrame.Reveal(progress: tween(ev.failed + C.statusRingSignDelaySeconds, C.statusRingSignSeconds, .easeOut),
                                          wipes: !rm)

        if ev.start == .ready {
            return StatusRingFrame(layers: [layer([.ring(alpha: C.statusRingDone), .check(.init(progress: 1, wipes: !rm))])], akane: 0)
        }
        if ev.start == .failed {
            // Failed before it appeared: the sign shows at once.
            let marks: [StatusRingFrame.Mark] = ev.base.map { download($0, breath: 0) } ?? [.ring(alpha: C.statusRingFailedRing)]
            return StatusRingFrame(layers: [layer(marks + [.exclamation(.init(progress: 1, wipes: !rm))])], akane: 1)
        }
        if t >= ev.failed {
            let akane = tween(ev.failed + C.statusRingAkaneDelaySeconds, C.statusRingAkaneSeconds)
            if ev.failed < prepared {
                // During the download: the head stops breathing, the ring turns akane where it
                // stands, then the sign.
                let breath = breath(at: ev.failed, reduceMotion: rm) * (1 - tween(ev.failed, C.statusRingSettleSeconds))
                return StatusRingFrame(layers: [layer(download(fraction(at: t, events: ev) ?? 0, breath: breath) + [.exclamation(sign)])],
                                       akane: akane)
            }
            // After it: the light stops and fades, and the whole ring rises to the failed strength.
            let tau = ev.failed - prepared, from = preparingStrength(tau)
            var layers = [layer([.ring(alpha: from + (C.statusRingFailedRing - from) * akane)])]
            if !rm { layers.append(layer([.light(angle: lightAngle(tau), alpha: light)], 1 - tween(ev.failed, C.statusRingSettleSeconds))) }
            layers.append(layer([.exclamation(sign)]))
            return StatusRingFrame(layers: layers, akane: akane)
        }
        if t >= ev.ready {
            // The light spreads into the ring, which rises to done, and the check is revealed.
            let from = preparingStrength(ev.ready - prepared)
            var layers: [StatusRingFrame.Layer] = []
            if handOff < 1 { layers.append(layer(closing(), 1 - handOff)) }
            layers.append(layer([.ring(alpha: from + (C.statusRingDone - from) * tween(ev.ready, C.statusRingReadyRingSeconds))]))
            if !rm {
                layers.append(layer([.light(angle: lightAngle(t - prepared), alpha: light)],
                                    1 - tween(ev.ready, C.statusRingReadyLightOutSeconds)))
            }
            let check = tween(ev.ready + C.statusRingCheckDelaySeconds, C.statusRingCheckSeconds, .easeOut)
            layers.append(layer([.check(.init(progress: check, wipes: !rm))]))
            return StatusRingFrame(layers: layers, akane: 0)
        }
        if t >= prepared {
            // The closed arc hands over to the turning light.
            let picture = layer(preparing(t - prepared), handOff)
            return StatusRingFrame(layers: handOff < 1 ? [layer(closing(), 1 - handOff), picture] : [picture], akane: 0)
        }
        return StatusRingFrame(layers: [layer(download(fraction(at: t, events: ev) ?? 0, breath: breath(at: t, reduceMotion: rm)))],
                               akane: 0)
    }

    /// The download at `fraction`: the faint track, the arc that has arrived over it, and the head,
    /// dimmed by `breath`.
    static func download(_ fraction: Double, breath: Double) -> [StatusRingFrame.Mark] {
        typealias C = Constants
        let head = C.statusRingDone - C.statusRingBreathDepth * breath
        return [.ring(alpha: C.statusRingTrack),
                .arc(fraction: fraction, alpha: over(C.statusRingUnderWay, C.statusRingTrack)),
                .head(fraction: fraction, alpha: over(head, C.statusRingUnderWay))]
    }

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

    // Where `t` is in its period, 0 to 1.
    private static func cycle(_ t: Double, _ period: Double) -> Double {
        let r = t.truncatingRemainder(dividingBy: period)
        return (r < 0 ? r + period : r) / period
    }

    // 0, up to 1, back to 0 across one cycle.
    private static func bump(_ x: Double) -> Double { 0.5 - 0.5 * cos(2 * .pi * x) }
}
