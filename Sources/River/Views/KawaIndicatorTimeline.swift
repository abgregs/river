import Foundation

/// A CSS-style cubic-Bézier easing curve from (0, 0) to (1, 1), solved by bisection exactly as
/// the study page solves it, so a curve here gives the study's value at the same time.
struct CubicBezier {
    let x1, y1, x2, y2: Double

    func callAsFunction(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        func bx(_ t: Double) -> Double { 3 * x1 * t * (1 - t) * (1 - t) + 3 * x2 * t * t * (1 - t) + t * t * t }
        func by(_ t: Double) -> Double { 3 * y1 * t * (1 - t) * (1 - t) + 3 * y2 * t * t * (1 - t) + t * t * t }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<24 {
            t = (lo + hi) / 2
            if bx(t) < x { lo = t } else { hi = t }
        }
        return by(t)
    }

    /// Things arriving: a strong ease-out.
    static let easeOut = CubicBezier(x1: 0.23, y1: 1, x2: 0.32, y2: 1)
    /// A material forming or lifting.
    static let easeInOut = CubicBezier(x1: 0.65, y1: 0, x2: 0.35, y2: 1)
    /// The panel leaving, softer than it arrived.
    static let exitOut = CubicBezier(x1: 0.33, y1: 1, x2: 0.68, y2: 1)
    /// A sine ease-in-out: the muted strokes' own unhurried fade.
    static let gentle = CubicBezier(x1: 0.37, y1: 0, x2: 0.63, y2: 1)
}

/// What has happened in one indicator cycle, in seconds on the cycle's clock. A moment that has
/// not happened yet is `.infinity`, so every envelope that waits on it holds.
struct KawaIndicatorEvents: Equatable {
    /// The panel leaves rest: a recording starts, or the model starts preparing.
    var press: Double
    /// The first level reading of the recording. Never, for a dead microphone or while preparing.
    var audio: Double = .infinity
    /// The recording ends (or preparing does).
    var release: Double = .infinity
    /// The text is typed and River is idle again. The same moment as `release` for a cancel or
    /// the end of preparing.
    var typed: Double = .infinity
}

/// Every envelope of the panel at one moment, each 0…1 unless noted.
struct KawaIndicatorChannels: Equatable {
    /// The panel's opacity.
    var panel: Double
    /// How far the panel sits below its place, in points.
    var rise: Double
    /// The muted strokes' presence (drawn at `Constants.kawaMutedOpacity` times this).
    var muted: Double
    /// Glass: how far the frost has formed.
    var form: Double
    /// Glass: how far the ink under the frost has risen from muted.
    var inkUp: Double
    /// Glass: the clock the frost's clearing reads, which stops at release so the frost does
    /// not return before it lifts.
    var clearTime: Double
    /// When the Glass layer starts, on the cycle's clock (`.infinity` until audio flows).
    var live: Double
}

/// The indicator's choreography, ported from the study's `channels()` (docs/design/studies/kawa/
/// kawa-studies-r1.html). Entry runs as a sequence: the panel, then the muted strokes, then the
/// Glass layer, which starts only once audio flows and a little before the strokes are fully
/// in. Exit runs it back. Pure, so every moment of it is unit-tested.
enum KawaIndicatorTimeline {
    static func channels(at t: Double, events ev: KawaIndicatorEvents, reduceMotion: Bool) -> KawaIndicatorChannels {
        typealias C = Constants
        // Reduce Motion: every change becomes a plain linear fade.
        func tween(_ start: Double, _ duration: Double, _ curve: CubicBezier = .easeOut) -> Double {
            reduceMotion ? min(1, max(0, (t - start) / C.kawaReducedFadeSeconds)) : curve(min(1, max(0, (t - start) / duration)))
        }
        let live = self.live(ev)
        // Exit mirrors the entry: the layer leaves first, over the time it took to arrive; the
        // strokes start their fade the same overlap before it finishes, or hold until the text is
        // typed while River transcribes; the panel finishes just after the strokes, as it led them in.
        let layerOut = ev.release + C.kawaLayerOutDelaySeconds
        let strokesOut = Self.strokesOut(ev)
        let panelIn = tween(ev.press, C.kawaPanelInSeconds)
        let panelOut = tween(panelOutStart(ev), C.kawaPanelOutSeconds, .exitOut)
        // Glass: the frost forms and the ink rises under it from the same moment, so the mark
        // never dims under fresh frost; on release both run back over the same durations.
        let form = tween(live, C.kawaGlassFormSeconds, .easeInOut) * (1 - tween(layerOut, C.kawaGlassFormSeconds, .easeInOut))
        let inkUp = tween(live, C.kawaGlassInkSeconds, .easeInOut) * (1 - tween(layerOut, C.kawaGlassInkSeconds, .easeInOut))
        return KawaIndicatorChannels(
            panel: panelIn * (1 - panelOut),
            rise: reduceMotion ? 0 : C.kawaPanelRise * (1 - panelIn) + C.kawaPanelRise * panelOut,
            muted: tween(ev.press + C.kawaMutedDelaySeconds, C.kawaMutedFadeSeconds, .gentle)
                * (1 - tween(strokesOut, C.kawaMutedFadeSeconds, .gentle)),
            form: form,
            inkUp: inkUp,
            clearTime: min(t, ev.release),
            live: live)
    }

    /// Whether the voice drives the layer at `t`: from when the layer starts until release. The
    /// one statement of the rule; the engine reads it at each of its steps.
    static func isOn(at t: Double, events ev: KawaIndicatorEvents) -> Bool {
        t >= live(ev) && t < ev.release
    }

    /// When the layer starts: the overlap before the muted strokes are in, or when audio first
    /// flows if that is later. Never, for a dead microphone.
    static func live(_ ev: KawaIndicatorEvents) -> Double {
        guard ev.audio.isFinite else { return .infinity }
        let strokesIn = ev.press + Constants.kawaMutedDelaySeconds + Constants.kawaMutedFadeSeconds
        return max(strokesIn - Constants.kawaLayerOverlapSeconds, ev.audio)
    }

    /// When the panel is fully gone, on the cycle's clock.
    static func end(_ ev: KawaIndicatorEvents, reduceMotion: Bool) -> Double {
        panelOutStart(ev) + (reduceMotion ? Constants.kawaReducedFadeSeconds : Constants.kawaPanelOutSeconds)
    }

    /// From when nothing on the panel can move until the next event: the muted strokes are in
    /// and the layer is still waiting for audio, as while preparing or with a dead microphone.
    /// Nil once audio flows or the cycle is released, when the panel always has motion to come.
    static func stillFrom(_ ev: KawaIndicatorEvents) -> Double? {
        guard !ev.audio.isFinite, !ev.release.isFinite else { return nil }
        return ev.press + Constants.kawaMutedDelaySeconds + Constants.kawaMutedFadeSeconds
    }

    /// The longest the panel can take to leave once River is idle: a release and the text typed
    /// at the same moment (a cancel, or preparing ending), without Reduce Motion. The window
    /// stays up this long so the exit is never cut off.
    static let longestExit: Double = end(KawaIndicatorEvents(press: 0, release: 0, typed: 0), reduceMotion: false)

    private static func strokesOut(_ ev: KawaIndicatorEvents) -> Double {
        let layerEnd = ev.release + Constants.kawaLayerOutDelaySeconds + Constants.kawaLayerOutSeconds
        return max(ev.typed, layerEnd - Constants.kawaLayerOverlapSeconds)
    }

    private static func panelOutStart(_ ev: KawaIndicatorEvents) -> Double {
        strokesOut(ev) + Constants.kawaMutedFadeSeconds + Constants.kawaMutedDelaySeconds - Constants.kawaPanelOutSeconds
    }
}

/// One pass of the mark through the panel: from leaving rest until its exit has finished. It
/// keeps the events the timeline reads on its own clock.
struct KawaIndicatorCycle: Equatable {
    let id = UUID()
    /// The moment the cycle's clock reads 0.
    let start: Date
    /// What the mark is showing: listening or preparing.
    let activity: MarkActivity
    private(set) var events = KawaIndicatorEvents(press: 0)

    /// Seconds on the cycle's clock at `date`.
    func time(at date: Date) -> Double { date.timeIntervalSince(start) }

    /// When the panel is gone, or nil while it is still waiting on an event.
    func end(reduceMotion: Bool) -> Date? {
        events.typed.isFinite ? start.addingTimeInterval(KawaIndicatorTimeline.end(events, reduceMotion: reduceMotion)) : nil
    }

    /// The cycle after River's activity, or the microphone, changes at `date`. A recording or
    /// preparing starts a cycle; audio flowing starts the layer; the end of the recording
    /// releases it; rest marks the text typed. A new recording while the last cycle is still
    /// leaving starts a new one, taking over the panel at the opacity it had reached.
    static func next(_ cycle: KawaIndicatorCycle?, activity: MarkActivity, isAudioFlowing: Bool,
                     reduceMotion: Bool, at date: Date) -> KawaIndicatorCycle? {
        switch activity {
        case .listening, .preparing:
            guard var cycle, cycle.activity == activity, !cycle.events.release.isFinite else {
                let opacity = cycle.map { KawaIndicatorTimeline.channels(at: $0.time(at: date), events: $0.events, reduceMotion: reduceMotion).panel } ?? 0
                let resumed = KawaIndicatorCycle(start: date.addingTimeInterval(-pressOffset(forPanel: opacity, reduceMotion: reduceMotion)),
                                                 activity: activity)
                return next(resumed, activity: activity, isAudioFlowing: isAudioFlowing, reduceMotion: reduceMotion, at: date)
            }
            if activity == .listening, isAudioFlowing, !cycle.events.audio.isFinite { cycle.events.audio = cycle.time(at: date) }
            return cycle
        case .transcribing:
            guard var cycle else { return nil }
            if !cycle.events.release.isFinite { cycle.events.release = cycle.time(at: date) }
            return cycle
        case .rest:
            guard var cycle else { return nil }
            let now = cycle.time(at: date)
            if !cycle.events.release.isFinite { cycle.events.release = now }
            if !cycle.events.typed.isFinite { cycle.events.typed = now }
            return cycle
        }
    }

    // How long after its press a cycle's panel reaches `opacity`, so a new cycle picks up where
    // the leaving one is instead of flashing back to transparent.
    private static func pressOffset(forPanel opacity: Double, reduceMotion: Bool) -> Double {
        guard opacity > 0 else { return 0 }
        let events = KawaIndicatorEvents(press: 0)
        var lo = 0.0, hi = Constants.kawaPanelInSeconds
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if KawaIndicatorTimeline.channels(at: mid, events: events, reduceMotion: reduceMotion).panel < opacity { lo = mid } else { hi = mid }
        }
        return hi
    }
}
