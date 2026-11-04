import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import River

// The `inputLevel` a microphone reading of this many decibels of full scale publishes.
func inputLevel(decibels: Double) -> Double {
    pow(10, decibels / 20) / Double(Constants.inputLevelReferenceRMS)
}

// Loudness at a built-in mic, from the maintainer's level trace (2026-11-02): a quiet room,
// and the loud end of soft, normal and raised speech.
let roomToneDecibels = -60.0
let softSpeechDecibels = -37.0
let speechDecibels = -31.0
let raisedSpeechDecibels = -22.0

// The study's dictation script (docs/design/studies/kawa/kawa-studies-r1.html, `SCRIPTS`):
// press at 0.3 s, the microphone live at 0.32, release at 6.2, the text typed at 6.9.
let dictation = KawaIndicatorEvents(press: 0.3, audio: 0.32, release: 6.2, typed: 6.9)

// The study's simulated voice, `sentence()`: words of random length and loudness from a seeded
// generator, each swelling and fading, with a pause. Ported so the engine can be run on exactly
// the input the golden values below came from.
func sentence(_ start: Double, _ end: Double, pauseAt: Double, pauseLength: Double, seed: Int,
                      low: Double = 0.45, span: Double = 0.5) -> (Double) -> Double {
    var x = seed
    func random() -> Double {
        x = (x * 16807) % 2_147_483_647
        return Double(x) / 2_147_483_647
    }
    var words: [(start: Double, length: Double, loudness: Double)] = []
    var t = start
    while t < end {
        if t > pauseAt, t < pauseAt + pauseLength { t = pauseAt + pauseLength; continue }
        let length = 0.16 + random() * 0.3
        words.append((t, length, low + random() * span))
        t += length + 0.04 + random() * 0.12
    }
    return { t in
        var v = 0.0
        for word in words where t > word.start && t < word.start + word.length {
            let u = (t - word.start) / word.length
            v = max(v, word.loudness * pow(sin(.pi * u), 0.6) * (0.78 + 0.22 * sin(2 * .pi * 5.5 * t + word.start * 9)))
        }
        return min(1, max(0, v))
    }
}

let dictationVoice = sentence(1.3, 5.7, pauseAt: 3.2, pauseLength: 0.75, seed: 11)

private struct Run {
    var engine: KawaIndicatorEngine
    /// Every drop, including those that have since faded.
    var drops: [KawaIndicatorEngine.Drop] = []
    /// The level as each drop fell.
    var levelsAtDrops: [Double] = []
}

// Runs the engine `fps` times a second, collecting every drop. The default is the study's own
// rate, one advance per step.
private func run(_ events: KawaIndicatorEvents, voice: (Double) -> Double, until end: Double,
                 fps: Double = Constants.kawaEngineStepsPerSecond, seed: Int = 0, reduceMotion: Bool = false) -> Run {
    var result = Run(engine: KawaIndicatorEngine(seed: seed))
    for i in 0...Int(end * fps) {
        let t = Double(i) / fps
        result.engine.advance(to: t, loudness: voice(t), events: events, reduceMotion: reduceMotion)
        for drop in result.engine.drops where !result.drops.contains(drop) {
            result.drops.append(drop)
            result.levelsAtDrops.append(result.engine.level)
        }
    }
    return result
}

// The distance from a point to the nearest point of a polyline.
private func distance(_ p: CGPoint, toPolyline points: [CGPoint]) -> Double {
    zip(points, points.dropFirst()).map { a, b in
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y), ap = CGPoint(x: p.x - a.x, y: p.y - a.y)
        let f = min(1, max(0, (ap.x * ab.x + ap.y * ab.y) / max(1e-12, ab.x * ab.x + ab.y * ab.y)))
        return hypot(p.x - (a.x + ab.x * f), p.y - (a.y + ab.y * f))
    }.min()!
}

@Suite("KawaIndicatorTimeline")
struct KawaIndicatorTimelineTests {
    private func at(_ t: Double, _ events: KawaIndicatorEvents = dictation, reduceMotion: Bool = false) -> KawaIndicatorChannels {
        KawaIndicatorTimeline.channels(at: t, events: events, reduceMotion: reduceMotion)
    }

    // Golden values from the Glass study's own `channels()` (docs/design/studies/kawa/
    // kawa-glass.template-r1.html), run in node on the values the maintainer chose there on
    // 2026-11-03: the frost forms and the ink rises over 0.6 s. The maintainer approved the
    // motion on those pages; this holds the app to it, number for number.
    @Test("every envelope matches the study at key moments of a dictation")
    func matchesStudy() {
        // t, panel, rise, muted, form, inkUp
        let golden: [[Double]] = [
            [0.3, 0, 6, 0, 0, 0], [0.4, 0.950923, 0.294461, 0.004791, 0, 0],
            [0.5, 0.9999, 0.000599, 0.163568, 0, 0], [0.605, 1, 0, 0.5, 0, 0],
            [0.7, 1, 0, 0.809778, 0.012455, 0.012455], [0.9, 1, 0, 1, 0.363, 0.363],
            [1, 1, 0, 1, 0.778019, 0.778019], [1.1, 1, 0, 1, 0.949872, 0.949872],
            [1.5, 1, 0, 1, 1, 1], [6.2, 1, 0, 1, 1, 1],
            [6.3, 1, 0, 1, 0.993927, 0.993927], [6.55, 1, 0, 1, 0.5, 0.5],
            [6.8, 1, 0, 1, 0.006073, 0.006073], [6.95, 1, 0, 0.970336, 0, 0],
            [7.2, 0.45115, 3.293098, 0.248065, 0, 0], [7.4, 0.0011, 5.993401, 0, 0, 0],
        ]
        for row in golden {
            let c = at(row[0])
            let got = [c.panel, c.rise, c.muted, c.form, c.inkUp]
            for (value, want) in zip(got, row.dropFirst()) {
                #expect(abs(value - want) < 1e-5, "t = \(row[0]): \(got) vs \(Array(row.dropFirst()))")
            }
        }
    }

    @Test("the muted strokes rise from 0.38 to 0.83 s after a press at 0.3 s")
    func mutedStrokesRise() {
        #expect(at(0.38).muted == 0)
        #expect(abs(at(0.605).muted - 0.5) < 1e-6)   // the sine ease-in-out is symmetric
        #expect(abs(at(0.83).muted - 1) < 1e-9)
        // They come in only once the panel is nearly in, so the two read as a sequence.
        #expect(at(0.38).panel > 0.85)
    }

    @Test("the layer starts 0.2 s before the strokes are fully in")
    func layerOverlapsStrokes() {
        #expect(abs(at(1).live - 0.63) < 1e-9)
        #expect(at(0.629).form == 0)
        #expect(at(0.64).form > 0)
        #expect(at(0.64).muted < 1)                  // still coming in as the layer starts
    }

    @Test("a microphone that delivers late starts the layer when audio arrives")
    func lateAudio() {
        let late = KawaIndicatorEvents(press: 0.3, audio: 1.5)
        #expect(at(1.49, late).form == 0)
        #expect(at(1.49, late).muted == 1)
        #expect(at(1.6, late).form > 0)
    }

    // A dead microphone must never look live: no layer, no voice, only the muted strokes.
    @Test("with no audio the layer never starts, and the muted strokes stay")
    func deadMicrophone() {
        let dead = KawaIndicatorEvents(press: 0.3)
        for t in stride(from: 0.0, through: 30, by: 0.05) {
            let c = at(t, dead)
            #expect(c.form == 0 && c.inkUp == 0 && !KawaIndicatorTimeline.isOn(at: t, events: dead))
        }
        #expect(at(30, dead).muted == 1)
        #expect(at(30, dead).panel == 1)
    }

    @Test("on release the layer leaves first, over the time it took to arrive")
    func layerLeavesFirst() {
        #expect(at(6.25).form == 1)                  // 0.05 s after release
        #expect(at(6.86).form == 0)                  // gone 0.6 s later
        #expect(at(6.86).inkUp == 0)
        #expect(at(6.86).muted == 1)                 // the strokes still hold
        #expect(!KawaIndicatorTimeline.isOn(at: 6.2, events: dictation))
    }

    // While River transcribes, the strokes are the only sign it is still working.
    @Test("the strokes and the panel hold until the text is typed")
    func holdsWhileTranscribing() {
        let transcribing = KawaIndicatorEvents(press: 0.3, audio: 0.32, release: 6.2)
        #expect(at(60, transcribing).muted == 1)
        #expect(at(60, transcribing).panel == 1)
        #expect(at(6.9).muted == 1)
        #expect(at(6.9 + Constants.kawaMutedFadeSeconds).muted == 0)
    }

    @Test("the panel finishes just after the strokes, as it led them in")
    func panelLeavesLast() {
        let strokesGone = 6.9 + Constants.kawaMutedFadeSeconds
        #expect(at(strokesGone).panel > 0)
        let end = KawaIndicatorTimeline.end(dictation, reduceMotion: false)
        #expect(abs(end - (strokesGone + Constants.kawaMutedDelaySeconds)) < 1e-9)
        #expect(at(end).panel == 0)
        #expect(at(end).rise == Constants.kawaPanelRise)
    }

    // Exit mirrors entry: on a cancel the strokes start leaving the same overlap before the
    // layer is gone that they finished arriving after it started.
    @Test("on a cancel the strokes leave the overlap before the layer is gone")
    func cancelOverlaps() {
        let cancel = KawaIndicatorEvents(press: 0.3, audio: 0.32, release: 3, typed: 3)
        let layerEnd = 3 + Constants.kawaLayerOutDelaySeconds + Constants.kawaLayerOutSeconds
        #expect(at(layerEnd - Constants.kawaLayerOverlapSeconds, cancel).muted == 1)
        #expect(at(layerEnd - 0.1, cancel).muted < 1)
        #expect(at(layerEnd - 0.1, cancel).form > 0)
        #expect(abs(KawaIndicatorTimeline.end(cancel, reduceMotion: false) - (3 + KawaIndicatorTimeline.longestExit)) < 1e-9)
    }

    // The panel stops redrawing from this moment, so nothing may still be moving then; and it
    // must never stop while audio could drive the layer or an exit is to come.
    @Test("the panel is still once the muted strokes are in and nothing else is coming")
    func stillPoint() throws {
        let preparing = KawaIndicatorEvents(press: 0.3)
        let still = try #require(KawaIndicatorTimeline.stillFrom(preparing))
        for reduceMotion in [false, true] {
            let atStill = at(still, preparing, reduceMotion: reduceMotion)
            let later = at(still + 60, preparing, reduceMotion: reduceMotion)
            #expect(abs(atStill.muted - later.muted) < 1e-9 && atStill.panel == later.panel && atStill.rise == later.rise)
        }
        #expect(KawaIndicatorTimeline.stillFrom(dictation) == nil)
        #expect(KawaIndicatorTimeline.stillFrom(KawaIndicatorEvents(press: 0.3, release: 2)) == nil)
    }

    // The coordinator keeps the window up this long; any longer exit would be cut off.
    @Test("the longest exit after River goes idle is a cancel's, 0.78 s")
    func longestExit() {
        #expect(abs(KawaIndicatorTimeline.longestExit - 0.78) < 1e-9)
        for release in stride(from: 0.0, through: 3, by: 0.25) {
            for reduceMotion in [false, true] {
                let events = KawaIndicatorEvents(press: 0, audio: 0.02, release: release, typed: 3)
                #expect(KawaIndicatorTimeline.end(events, reduceMotion: reduceMotion) - 3 <= KawaIndicatorTimeline.longestExit + 1e-9)
            }
        }
    }

    @Test("under Reduce Motion every envelope is a 0.2 s linear fade, with no rise")
    func reduceMotion() {
        #expect(at(0.3, reduceMotion: true).rise == 0)
        #expect(abs(at(0.4, reduceMotion: true).panel - 0.5) < 1e-9)
        #expect(abs(at(0.48, reduceMotion: true).muted - 0.5) < 1e-9)
        #expect(abs(at(0.58, reduceMotion: true).muted - 1) < 1e-9)
        #expect(abs(at(0.73, reduceMotion: true).form - 0.5) < 1e-9)
        #expect(at(KawaIndicatorTimeline.end(dictation, reduceMotion: true), reduceMotion: true).panel == 0)
    }

    @Test("the curves start at 0, end at 1, and solve the study's control points")
    func curves() {
        for curve in [CubicBezier.easeOut, .easeInOut, .exitOut, .gentle] {
            #expect(curve(0) == 0)
            #expect(curve(1) == 1)
            #expect(curve(0.25) < curve(0.5) && curve(0.5) < curve(0.75))
        }
        #expect(abs(CubicBezier.gentle(0.5) - 0.5) < 1e-6)
        #expect(CubicBezier.easeOut(0.2) > 0.6)       // arrives fast
    }
}

@Suite("KawaIndicatorEngine")
struct KawaIndicatorEngineTests {
    @Test("the hash matches the study's, bit for bit")
    func hash() {
        let golden = [(7, 0, 0.22717), (11, 3, 0.986695), (13, 12345, 0.943146), (19, 99, 0.896254)]
        for (i, n, want) in golden { #expect(abs(KawaIndicatorEngine.hash(i, n) - want) < 1e-6) }
    }

    // Golden values from the study's `runScript` on the dictation script. Matching them means
    // the level, the cadence, the tiers and the placement are all the approved ones.
    @Test("a dictation drops the study's drops, at the same moments, places and tiers")
    func matchesStudyDrops() {
        let allDrops = run(dictation, voice: dictationVoice, until: 6.5).drops
        // x, y, time, tier
        let golden: [[Double]] = [
            [15.742738, 30.06884, 1.3375, 0], [23.490739, 26.076707, 1.8375, 2],
            [30.640291, 34.809643, 2.3375, 2], [31.321861, 28.409061, 2.8375, 1],
            [23.327205, 22.88139, 3.3375, 2], [16.665329, 23.29718, 3.991667, 1],
            [24.198644, 25.0258, 4.495833, 2], [23.364013, 23.03741, 4.995833, 2],
            [23.730477, 23.241669, 5.495833, 1], [31.91368, 20.245167, 5.995833, 1],
        ]
        #expect(allDrops.count == golden.count)
        for (drop, want) in zip(allDrops, golden) {
            #expect(abs(drop.x - want[0]) < 1e-4 && abs(drop.y - want[1]) < 1e-4, "\(drop) vs \(want)")
            #expect(abs(drop.time - want[2]) < 1e-5)
            #expect(drop.tier == Int(want[3]))
        }
    }

    // The tier is how loud the voice was, and Glass shows it twice: a louder voice rings
    // stronger and clears a wider window. A tier that rang or cleared no more than the one below
    // would make raised speech read like normal speech.
    @Test("ring strength and window radius rise from soft to normal to raised")
    func tiersRise() {
        let drops = (0...2).map { KawaIndicatorEngine.drop(0, at: 0, tier: $0, peak: 0) }
        for (quieter, louder) in zip(drops, drops.dropFirst()) {
            #expect(quieter.strength < louder.strength)
            #expect(quieter.windowRadius < louder.windowRadius)
        }
        // A raised voice's window stays inside the panel: the mark's own 48 pt square.
        #expect(drops[2].windowRadius < Constants.indicatorPanelWidth)
    }

    // The shader fades a window back to frost from `hold` to `hold + fade` after its drop; it can
    // only do that while the engine still hands it the drop. A drop forgotten earlier would snap
    // its window shut instead. (The fade itself is shader-only, so it has no Swift-side test.)
    @Test("a drop stays in the engine until its window has faded back to frost")
    func dropOutlivesItsWindow() throws {
        let speaking = KawaIndicatorEvents(press: 0, audio: 0.02, release: 10)
        let voice: (Double) -> Double = { t in t >= 1 && t < 1.1 ? 0.7 : 0 }
        var engine = KawaIndicatorEngine(seed: 0)
        for i in 0...Int(1.2 * Constants.kawaEngineStepsPerSecond) {
            let t = Double(i) / Constants.kawaEngineStepsPerSecond
            engine.advance(to: t, loudness: voice(t), events: speaking, reduceMotion: false)
        }
        let drop = try #require(engine.drops.first)
        #expect(engine.drops.count == 1)
        let faded = drop.time + Constants.kawaGlassWindowHoldSeconds + Constants.kawaGlassWindowFadeSeconds
        engine.advance(to: faded - 0.01, loudness: 0, events: speaking, reduceMotion: false)
        #expect(engine.drops == [drop])
        engine.advance(to: drop.time + Constants.kawaGlassDropSeconds, loudness: 0, events: speaking, reduceMotion: false)
        #expect(engine.drops.isEmpty)
    }

    @Test("ripples fall about twice a second while the voice is above the threshold, at any frame rate")
    func cadence() {
        let speaking = KawaIndicatorEvents(press: 0, audio: 0.02, release: 5.6)
        for fps in [60.0, 120.0, 47.0] {
            let drops = run(speaking, voice: { $0 > 1.5 ? 0.7 : 0 }, until: 5.5, fps: fps).drops
            // 1.5 … 5.5 s: 4 s at 2 a second, the first on the rising edge.
            #expect((8...9).contains(drops.count), "\(drops.count) at \(fps) fps")
            for (a, b) in zip(drops, drops.dropFirst()) { #expect(b.time - a.time >= 0.5 - 1e-9) }
        }
    }

    // Quiet background sound must leave the glass still, so stillness means silence.
    @Test("no ripples fall below the threshold")
    func belowThreshold() {
        let speaking = KawaIndicatorEvents(press: 0, audio: 0.02, release: 10)
        let voice = Constants.kawaGlassThreshold / 1.25    // the jitter lifts it at most 18 %
        let result = run(speaking, voice: { _ in voice }, until: 6, fps: 60)
        #expect(result.drops.isEmpty)
        #expect(result.engine.level > 0)
    }

    @Test("a drop's tier is the tier of the loudest level since the previous drop")
    func tiers() {
        #expect(KawaIndicatorEngine.tier(peak: Constants.kawaGlassThreshold) == 0)
        #expect(KawaIndicatorEngine.tier(peak: 0.3199) == 0)
        #expect(KawaIndicatorEngine.tier(peak: 0.32) == 1)
        #expect(KawaIndicatorEngine.tier(peak: 0.5999) == 1)
        #expect(KawaIndicatorEngine.tier(peak: 0.6) == 2)
        #expect(KawaIndicatorEngine.tier(peak: 1) == 2)

        // A loud syllable just after a drop, then quieter speech when the next one falls: the
        // next drop still reads loud, though the level at that moment alone would read normal.
        let speaking = KawaIndicatorEvents(press: 0, audio: 0.02, release: 10)
        let voice: (Double) -> Double = { t in t < 1 ? 0 : t < 1.1 ? 0.25 : t < 1.25 ? 0.95 : 0.2 }
        let result = run(speaking, voice: voice, until: 1.9)
        #expect(result.drops.count == 2)
        #expect(result.drops[0].tier == 0)        // the rising edge, barely over the threshold
        #expect(result.drops[1].tier == 2)
        #expect(result.drops[1].peak >= Constants.kawaGlassLoudFrom)
        #expect(result.levelsAtDrops[1] < Constants.kawaGlassLoudFrom)
    }

    // The drops are what makes the strokes look rippled; one that missed them would ripple
    // the empty panel.
    @Test("every drop lands on a stroke's spine, within its 0.6 pt nudge")
    func dropsOnSpines() {
        let spines = KawaMark.spines.map { $0.map { CGPoint(x: $0.x, y: $0.y).applying(KawaIndicatorEngine.panelTransform) } }
        for k in 0..<500 {
            let drop = KawaIndicatorEngine.drop(k, at: 0, tier: 1, peak: 0.5)
            let nearest = spines.map { distance(CGPoint(x: drop.x, y: drop.y), toPolyline: $0) }.min()!
            #expect(nearest <= 0.6 * 2.0.squareRoot() + 1e-9, "drop \(k) is \(nearest) pt off")
        }
    }

    @Test("each seed drops in a different order; the same seed repeats")
    func seeded() {
        let speaking = KawaIndicatorEvents(press: 0, audio: 0.02, release: 10)
        let a = run(speaking, voice: { _ in 0.7 }, until: 3, fps: 60, seed: 1).drops
        let b = run(speaking, voice: { _ in 0.7 }, until: 3, fps: 60, seed: 2).drops
        let again = run(speaking, voice: { _ in 0.7 }, until: 3, fps: 60, seed: 1).drops
        #expect(a == again)
        #expect(a.map(\.x) != b.map(\.x))
    }

    @Test("a dead microphone drops nothing and leaves the level at zero")
    func deadMicrophone() {
        let result = run(KawaIndicatorEvents(press: 0.3), voice: { _ in 0.8 }, until: 4, fps: 60)
        #expect(result.drops.isEmpty)
        #expect(result.engine.level == 0)
    }

    @Test("under Reduce Motion there are no ripples and no jitter: the level follows the voice")
    func reduceMotion() {
        let speaking = KawaIndicatorEvents(press: 0, audio: 0.02, release: 10)
        let result = run(speaking, voice: { _ in 0.7 }, until: 3, fps: 60, reduceMotion: true)
        #expect(result.drops.isEmpty)
        #expect(abs(result.engine.level - 0.7) < 1e-6)
    }

    @Test("the level rises fast and falls slowly, and settles to zero on release")
    func riseAndFall() {
        let events = KawaIndicatorEvents(press: 0, audio: 0.02, release: 2)
        var engine = KawaIndicatorEngine(seed: 0)
        engine.advance(to: 1, loudness: 0, events: events, reduceMotion: true)
        engine.advance(to: 1.1, loudness: 0.8, events: events, reduceMotion: true)
        let risen = engine.level
        engine.advance(to: 1.9, loudness: 0.8, events: events, reduceMotion: true)
        engine.advance(to: 2.1, loudness: 0.8, events: events, reduceMotion: true)
        let fallen = 0.8 - engine.level
        #expect(risen > 0.8 * 0.8)                  // most of the way up in 0.1 s
        #expect(fallen < 0.8 * 0.4)                 // well under halfway down in 0.1 s
        engine.advance(to: 5, loudness: 0.8, events: events, reduceMotion: true)
        #expect(engine.level < 1e-4)
        #expect(engine.drops.isEmpty)
    }

    // Under Reduce Motion the level clears the frost directly. If the clearing fell with the
    // level at release, the frost would fill back in while it is still lifting.
    @Test("under Reduce Motion the frost's clearing holds from release until the frost has lifted")
    func reduceMotionClearingHoldsThroughRelease() {
        let events = KawaIndicatorEvents(press: 0, audio: 0.02, release: 2)
        var engine = KawaIndicatorEngine(seed: 0)
        engine.advance(to: events.release, loudness: 0.8, events: events, reduceMotion: true)
        let atRelease = engine.clearing
        #expect(atRelease > 0.7)
        let lifted = events.release + Constants.kawaLayerOutDelaySeconds + Constants.kawaReducedFadeSeconds
        for t in stride(from: events.release, through: lifted, by: 0.01) {
            engine.advance(to: t, loudness: 0.8, events: events, reduceMotion: true)
            #expect(engine.clearing == atRelease, "at \(t) s")
        }
        #expect(engine.level < atRelease)           // the level itself has started to fall
    }

    @Test("loudness reads decibels between the trim's floor and the ceiling")
    func loudness() {
        #expect(KawaIndicatorEngine.loudness(level: 0) == 0)
        #expect(KawaIndicatorEngine.loudness(level: inputLevel(decibels: Constants.markMeterFloorDecibels - 1)) == 0)
        #expect(KawaIndicatorEngine.loudness(level: inputLevel(decibels: Constants.markMeterCeilingDecibels)) > 0.999)
    }

    // On the first device calibration soft speech filled half the scale and normal speech
    // nearly all of it, so raised speech had nowhere to go and a quiet voice looked loud. The
    // scale must keep a quiet room still and give each voice its own Glass strength.
    @Test("a quiet room reads silence; soft, normal and raised speech take the three strengths")
    func voicesReadApart() {
        func loudness(_ decibels: Double) -> Double { KawaIndicatorEngine.loudness(level: inputLevel(decibels: decibels)) }
        #expect(loudness(roomToneDecibels) == 0)
        let soft = loudness(softSpeechDecibels), normal = loudness(speechDecibels), raised = loudness(raisedSpeechDecibels)
        #expect(soft > Constants.kawaGlassThreshold && soft < Constants.kawaGlassNormalFrom, "soft: \(soft)")
        #expect(normal >= Constants.kawaGlassNormalFrom && normal < Constants.kawaGlassLoudFrom, "normal: \(normal)")
        #expect(raised >= Constants.kawaGlassLoudFrom, "raised: \(raised)")
        // Raised speech is not clipped before the indicator reads it.
        #expect(inputLevel(decibels: Constants.markMeterCeilingDecibels) <= 1)
    }
}

@Suite("KawaIndicatorCycle")
struct KawaIndicatorCycleTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    private func next(_ cycle: KawaIndicatorCycle?, _ activity: MarkActivity, audio: Bool = false,
                      at seconds: Double) -> KawaIndicatorCycle? {
        KawaIndicatorCycle.next(cycle, activity: activity, isAudioFlowing: audio, reduceMotion: false,
                                at: t0.addingTimeInterval(seconds))
    }

    @Test("a recording runs press, audio, release and typed on the cycle's clock")
    func recording() throws {
        var cycle = try #require(next(nil, .listening, at: 0))
        #expect(cycle.events == KawaIndicatorEvents(press: 0))
        #expect(cycle.end(reduceMotion: false) == nil)        // waits on the text being typed
        cycle = try #require(next(cycle, .listening, audio: true, at: 0.02))
        cycle = try #require(next(cycle, .listening, audio: true, at: 1))     // later readings change nothing
        cycle = try #require(next(cycle, .transcribing, at: 4))
        cycle = try #require(next(cycle, .rest, at: 5))
        #expect(abs(cycle.events.audio - 0.02) < 1e-9)
        #expect(abs(cycle.events.release - 4) < 1e-9)
        #expect(abs(cycle.events.typed - 5) < 1e-9)
        let end = try #require(cycle.end(reduceMotion: false))
        #expect(abs(end.timeIntervalSince(t0) - KawaIndicatorTimeline.end(cycle.events, reduceMotion: false)) < 1e-9)
    }

    @Test("a cancel releases and types at the same moment")
    func cancel() throws {
        let cycle = try #require(next(next(nil, .listening, audio: true, at: 0), .rest, at: 2))
        #expect(cycle.events.release == cycle.events.typed)
    }

    @Test("without audio, and while preparing, the layer's event never comes")
    func noAudio() throws {
        let dead = try #require(next(next(nil, .listening, at: 0), .listening, at: 3))
        #expect(!dead.events.audio.isFinite)
        let preparing = try #require(next(next(nil, .preparing, audio: true, at: 0), .rest, at: 3))
        #expect(!preparing.events.audio.isFinite)
        #expect(preparing.events.release == preparing.events.typed)
    }

    @Test("rest with no cycle shows nothing")
    func restIsEmpty() {
        #expect(next(nil, .rest, at: 0) == nil)
        #expect(next(nil, .transcribing, at: 0) == nil)
    }

    // Recording again while the last panel is still fading must not flash it to transparent.
    @Test("a new recording during the exit takes over the panel at the opacity it had reached")
    func pressDuringExit() throws {
        let leaving = try #require(next(next(nil, .listening, audio: true, at: 0), .rest, at: 2))
        let at = 2 + 0.6
        let before = KawaIndicatorTimeline.channels(at: leaving.time(at: t0.addingTimeInterval(at)), events: leaving.events, reduceMotion: false)
        #expect(before.panel > 0.05 && before.panel < 0.95)
        let again = try #require(next(leaving, .listening, at: at))
        #expect(again.id != leaving.id)
        let after = KawaIndicatorTimeline.channels(at: again.time(at: t0.addingTimeInterval(at)), events: again.events, reduceMotion: false)
        #expect(abs(after.panel - before.panel) < 1e-3)
        #expect(!again.events.release.isFinite)
    }
}

@Suite("MarkActivity")
struct MarkActivityTests {
    @Test("the mark listens while recording, transcribes while processing, and prepares only at idle")
    func mapping() {
        #expect(MarkActivity.of(state: .recording, isModelPreparing: false) == .listening)
        #expect(MarkActivity.of(state: .processing, isModelPreparing: false) == .transcribing)
        #expect(MarkActivity.of(state: .idle, isModelPreparing: true) == .preparing)
        #expect(MarkActivity.of(state: .idle, isModelPreparing: false) == .rest)
    }
}

@Suite("Indicator panel geometry")
struct IndicatorPanelGeometryTests {
    // A square a little smaller than a Dock icon at the default tile size, so the mark reads
    // as one more tile sitting just above the Dock.
    @Test("the panel is a 48 pt square: the 34 pt mark plus 7 pt on every side")
    func panelGeometry() {
        #expect(Constants.indicatorMarkSize == 34)
        #expect(Constants.indicatorPanelWidth == 48)
        #expect(Constants.indicatorPanelHeight == 48)
    }

    // Concentric radii: the message rectangle's radius is its padding plus a 4 pt inner radius.
    @Test("the message rectangle keeps the concentric 16 pt radius over 12 pt padding")
    func messageGeometry() {
        #expect(Constants.hudMessageCornerRadius == Constants.hudMessagePadding + 4)
        #expect(Constants.hudStackSpacing == 8)
    }

    // Every surface is lit from one place, the upper left, where Glass lights its ripples from.
    // A gradient pinned to fixed unit points would tilt that light with each shape's
    // proportions, so the square mark panel and the wide transcript would disagree.
    @Test("the surface's light runs from the upper-left corner to the lower-right one, at 147°, on any shape")
    func lightAxis() {
        for size in [CGSize(width: Constants.indicatorPanelWidth, height: Constants.indicatorPanelHeight),
                     CGSize(width: Constants.transcriptPanelWidth, height: Constants.transcriptPanelHeight)] {
            let axis = HUDSurface.lightAxis(in: size)
            let start = CGPoint(x: axis.start.x * size.width, y: axis.start.y * size.height)
            let end = CGPoint(x: axis.end.x * size.width, y: axis.end.y * size.height)
            let line = CGPoint(x: end.x - start.x, y: end.y - start.y)
            func along(_ p: CGPoint) -> Double {
                ((p.x - start.x) * line.x + (p.y - start.y) * line.y) / (line.x * line.x + line.y * line.y)
            }
            #expect(abs(along(.zero)) < 1e-9, "\(size)")
            #expect(abs(along(CGPoint(x: size.width, y: size.height)) - 1) < 1e-9, "\(size)")
            #expect(abs(Double(atan2(line.x, -line.y)) * 180 / Double.pi - Constants.hudLightAngle) < 1e-9, "\(size)")
        }
    }

    @Test("the fade is 0.22 s with a 6 pt rise")
    func fade() {
        #expect(Constants.hudFadeSeconds == 0.22)
        #expect(Constants.hudFadeRise == 6)
    }
}

// The seam between Swift and Metal is positional: a swapped pair of floats compiles and renders,
// just wrong. These hold `GlassRenderer.arguments` to the shader's own signature, without a GPU.
@Suite("GlassRenderer arguments")
struct GlassRendererArgumentTests {
    static let source = try! String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../Sources/River/Shaders/KawaGlass.metal").standardizedFileURL, encoding: .utf8)

    // `kawaGlass`'s parameters after the position and the layer, as (type, name).
    static let parameters: [(type: String, name: String)] = {
        let signature = source.components(separatedBy: "half4 kawaGlass(")[1].components(separatedBy: ")")[0]
        return signature.components(separatedBy: ",").dropFirst(2).map { parameter in
            let words = parameter.replacingOccurrences(of: "*", with: "* ").split(whereSeparator: \.isWhitespace).map(String.init)
            return (words.dropLast().joined(separator: " "), words.last!)
        }
    }()

    private let engine = run(dictation, voice: dictationVoice, until: 3).engine
    private let channels = KawaIndicatorTimeline.channels(at: 3, events: dictation, reduceMotion: false)

    private func arguments(reduceMotion: Bool = false, engine: KawaIndicatorEngine? = nil) -> [(name: String, value: GlassRenderer.Argument)] {
        GlassRenderer.arguments(channels: channels, time: 3, engine: engine ?? self.engine, reduceMotion: reduceMotion, colors: .dark)
    }

    private func value(_ name: String, in arguments: [(name: String, value: GlassRenderer.Argument)]) -> GlassRenderer.Argument? {
        arguments.first { $0.name == name }?.value
    }

    @Test("every argument is the shader's parameter of the same name, kind and place")
    func matchesTheShaderSignature() {
        // A float array reaches the shader as its floats and their count.
        let expected = arguments().flatMap { name, value -> [(type: String, name: String)] in
            switch value {
            case .float: [("float", name)]
            case .float2: [("float2", name)]
            case .color: [("half4", name)]
            case .floats: [("device const float *", name), ("int", "count")]
            }
        }
        #expect(Self.parameters.map(\.name) == expected.map(\.name))
        #expect(Self.parameters.map(\.type) == expected.map(\.type))
    }

    @Test("drops are packed at the shader's stride, in the order it reads them")
    func dropPacking() throws {
        #expect(Self.source.contains("constant int STRIDE = \(GlassRenderer.dropStride);"))
        let drops = engine.drops
        try #require(drops.count >= 2)
        let packed = GlassRenderer.packed(drops)
        #expect(packed.count == drops.count * GlassRenderer.dropStride)
        for (k, drop) in drops.enumerated() {
            let fields = Array(packed[k * GlassRenderer.dropStride..<(k + 1) * GlassRenderer.dropStride])
            #expect(fields == [Float(drop.x), Float(drop.y), Float(drop.time), Float(drop.strength), Float(drop.windowRadius)])
        }
        guard case .floats(let sent) = value("drops", in: arguments()) else { Issue.record("no drops argument"); return }
        #expect(sent == packed)
    }

    // The array argument can never be empty, so with no drops one is sent that has long faded.
    @Test("with no drops one spent drop is sent, older than any ripple or window lasts")
    func noDrops() {
        let packed = GlassRenderer.packed([])
        #expect(packed.count == GlassRenderer.dropStride)
        #expect(Double(-packed[2]) > Constants.kawaGlassDropSeconds)
    }

    // The engine drops a drop once its ripple and window are over; the shader ends the ripple on
    // the same number, so neither cuts the other off.
    @Test("the shader's ripple life is the engine's, and the engine keeps a drop that long")
    func rippleLife() {
        #expect(value("life", in: arguments()) == .float(Constants.kawaGlassRippleSeconds))
        #expect(Constants.kawaGlassDropSeconds >= Constants.kawaGlassRippleSeconds)
    }

    // The panel's lit edge and Glass's ripples share one light.
    @Test("the ripples are lit from where the surface's light comes from")
    func sharedLight() throws {
        guard case .float2(let x, let y) = value("light", in: arguments()) else { Issue.record("no light argument"); return }
        let surface = HUDSurface.lightDirection
        #expect(abs(x + surface.dx) < 1e-12 && abs(y + surface.dy) < 1e-12)
        #expect(abs(hypot(x, y) - 1) < 1e-12)
    }

    @Test("under Reduce Motion the shader is flat and cleared by the engine's held clearing")
    func reduceMotionClearing() {
        let events = KawaIndicatorEvents(press: 0, audio: 0.02, release: 2)
        var held = KawaIndicatorEngine(seed: 0)
        held.advance(to: 2.1, loudness: 0.8, events: events, reduceMotion: true)
        let sent = arguments(reduceMotion: true, engine: held)
        #expect(value("flat", in: sent) == .float(1))
        #expect(value("clearing", in: sent) == .float(held.clearing))
        #expect(held.clearing > 0.7)
    }
}

// The live panel's whole feed: a level reading in, the engine for this frame out.
@Suite("KawaIndicatorVoice")
struct KawaIndicatorVoiceTests {
    private func speak(_ voice: KawaIndicatorVoice, cycle: UUID, decibels: Double, until end: Double) -> KawaIndicatorEngine {
        var engine = KawaIndicatorEngine(seed: 0)
        for frame in 0...Int(end * 60) {
            engine = voice.engine(for: cycle, events: dictation, at: Double(frame) / 60,
                                  inputLevel: inputLevel(decibels: decibels), reduceMotion: false)
        }
        return engine
    }

    @Test("speech readings ripple and a quiet room's do not")
    func readsLoudness() {
        #expect(!speak(KawaIndicatorVoice(makeEngine: { KawaIndicatorEngine(seed: 0) }), cycle: UUID(),
                       decibels: speechDecibels, until: 3).drops.isEmpty)
        let quiet = speak(KawaIndicatorVoice(makeEngine: { KawaIndicatorEngine(seed: 0) }), cycle: UUID(), decibels: roomToneDecibels, until: 3)
        #expect(quiet.drops.isEmpty && quiet.level == 0)
    }

    // A new recording must not inherit the last one's drops or level.
    @Test("each new cycle starts a fresh engine; the same cycle carries on")
    func freshEnginePerCycle() {
        let voice = KawaIndicatorVoice(makeEngine: { KawaIndicatorEngine(seed: 0) })
        let first = UUID()
        let spoken = speak(voice, cycle: first, decibels: speechDecibels, until: 3)
        let same = voice.engine(for: first, events: dictation, at: 3, inputLevel: inputLevel(decibels: speechDecibels), reduceMotion: false)
        #expect(same.drops == spoken.drops && same.level == spoken.level)
        let next = voice.engine(for: UUID(), events: dictation, at: 0.1, inputLevel: inputLevel(decibels: speechDecibels), reduceMotion: false)
        #expect(next.drops.isEmpty && next.level == 0)
    }
}
