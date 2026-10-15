import Foundation
import Testing
@testable import River

// The `inputLevel` a microphone reading of this many decibels of full scale publishes.
func inputLevel(decibels: Double) -> Double {
    pow(10, decibels / 20) / Double(Constants.inputLevelReferenceRMS)
}

// Rough loudness at a built-in mic: quiet talking, normal speech.
let quietSpeechDecibels = -42.0
let speechDecibels = -32.0

// Steps a frame at a fixed rate, the way the indicator's TimelineView does.
extension StoneMarkFrame {
    func running(_ activity: MarkActivity, from start: Double, for seconds: Double, fps: Double = 60,
                 reduceMotion: Bool = false, level: (Double) -> Double = { _ in 0 },
                 each: (StoneMarkFrame) -> Void = { _ in }) -> (frame: StoneMarkFrame, end: Double) {
        var frame = self
        var now = start
        while now < start + seconds - 1e-9 {
            now += 1 / fps
            frame = frame.advanced(to: now, activity: activity, inputLevel: level(now), reduceMotion: reduceMotion)
            each(frame)
        }
        return (frame, now)
    }
}

// The clear space between two outlines in design units, or a negative number when they overlap.
func gap(_ a: [StoneMark.Point], _ b: [StoneMark.Point]) -> Double {
    func inside(_ p: StoneMark.Point, _ polygon: [StoneMark.Point]) -> Bool {
        var result = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let pi = polygon[i], pj = polygon[j]
            if (pi.y > p.y) != (pj.y > p.y), p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x { result.toggle() }
            j = i
        }
        return result
    }
    func toSegment(_ p: StoneMark.Point, _ a: StoneMark.Point, _ b: StoneMark.Point) -> Double {
        let d = b - a, length = (d * d).sum()
        let u = length > 0 ? min(1, max(0, ((p - a) * d).sum() / length)) : 0
        let e = p - (a + d * u)
        return (e * e).sum().squareRoot()
    }
    // Outlines whose boxes are well apart need no point-by-point measure.
    let boxA = StoneMark.boundingBox([a]), boxB = StoneMark.boundingBox([b])
    let boxGap = max(boxB.minX - boxA.maxX, boxA.minX - boxB.maxX, boxB.minY - boxA.maxY, boxA.minY - boxB.maxY)
    if boxGap > 20 { return boxGap }
    if a.contains(where: { inside($0, b) }) || b.contains(where: { inside($0, a) }) { return -1 }
    var closest = Double.infinity
    for (points, polygon) in [(a, b), (b, a)] {
        for p in points {
            for k in polygon.indices { closest = min(closest, toSegment(p, polygon[k], polygon[(k + 1) % polygon.count])) }
        }
    }
    return closest
}

@Suite("StoneMark shapes")
struct StoneMarkShapeTests {
    @Test("three stones, each resampled to four sides of 48 points, left to right")
    func pieces() {
        #expect(StoneMark.pieces.count == 3)
        #expect(StoneMark.pieces.allSatisfy { $0.count == 4 * StoneMark.pointsPerSide })
        let centers = StoneMark.pieces.map { outline in outline.map(\.x).reduce(0, +) / Double(outline.count) }
        #expect(centers == centers.sorted())
    }

    // A mark pushed to one side of its panel reads as a mistake (maintainer, 2026-10-14): the
    // r at rest and the landed bars both sit on the mark's center line.
    @Test("the mark is centered as the r and as bars")
    func centered() {
        let rest = StoneMarkFrame(seed: 1)
        let restBox = StoneMark.boundingBox((0..<3).map { rest.outline(ofPiece: $0) })
        #expect(abs(restBox.midX + rest.centering - StoneMark.bounds.midX) < 0.01)
        let bars = rest.running(.listening, from: 1_000, for: 1.5).frame
        let barsBox = StoneMark.boundingBox((0..<3).map { bars.outline(ofPiece: $0) })
        #expect(abs(barsBox.midX + bars.centering - StoneMark.bounds.midX) < 0.01)
    }

    // The cuts are 0.3 of the stem wide; rounding the corners must not close them.
    @Test("the stones at rest keep the water between them")
    func restingStonesAreApart() {
        #expect(gap(StoneMark.pieces[0], StoneMark.pieces[1]) > 30)
        #expect(gap(StoneMark.pieces[1], StoneMark.pieces[2]) > 30)
    }

    // At silence a bar is a stone, about as tall as it is wide; at full level it reaches the
    // r's x-height. Together the three span the mark's width.
    @Test("the bars run from a stone's height to the x-height across the mark's width")
    func bars() {
        let silent = StoneMark.bar(1, level: 0), full = StoneMark.bar(1, level: 1)
        let silentHeight = StoneMark.baseline - silent.map(\.y).min()!
        #expect(abs((silent.map(\.y).min()! - full.map(\.y).min()!) - (StoneMark.barMaxHeight - StoneMark.barMinHeight)) < 0.5)
        #expect(silentHeight < StoneMark.barWidth * 1.3)
        #expect(silent.map(\.y).max()! <= StoneMark.baseline + 0.5)
        #expect(abs(StoneMark.bar(0, level: 0).map(\.x).min()! - StoneMark.bounds.minX) < 0.5)
        #expect(abs(StoneMark.bar(2, level: 0).map(\.x).max()! - StoneMark.bounds.maxX) < 0.5)
        #expect(gap(StoneMark.bar(0, level: 1), StoneMark.bar(1, level: 1)) > 40)
    }
}

@Suite("StoneMarkPresentation")
struct StoneMarkPresentationTests {
    typealias Mark = StoneMarkPresentation

    // Solved, not stepped: the morph lands the same at any display rate.
    @Test("the spring gives the same morph at 60 and 120 frames a second")
    func springIsFrameRateIndependent() {
        func position(fps: Double) -> Double {
            var state = (position: 0.0, velocity: 0.0)
            for _ in 0..<Int(0.3 * fps) { state = Mark.spring(position: state.position, velocity: state.velocity, goal: 1, interval: 1 / fps) }
            return state.position
        }
        #expect(abs(position(fps: 60) - position(fps: 120)) < 1e-9)
    }

    // Critically damped: it settles without passing its goal, so a stone never overshoots its bar.
    @Test("the spring reaches its goal without overshooting")
    func springSettles() {
        var state = (position: 0.0, velocity: 0.0)
        var highest = 0.0
        for _ in 0..<120 {
            state = Mark.spring(position: state.position, velocity: state.velocity, goal: 1, interval: 1.0 / 120)
            highest = max(highest, state.position)
        }
        #expect(highest <= 1 + 1e-9)
        #expect(state.position > 0.99)
    }

    @Test("a bar reaches its level only as its stone lands")
    func morphLevel() {
        #expect(Mark.morphLevel(0.8, progress: 0) == 0)
        #expect(Mark.morphLevel(0.8, progress: 1) == 0.8)
        #expect(Mark.morphLevel(0.8, progress: 0.5) < 0.8 * 0.1)
    }

    @Test("loudness reads decibels between the trim's floor and the ceiling")
    func loudness() {
        #expect(Mark.loudness(level: 0) == 0)
        #expect(Mark.loudness(level: inputLevel(decibels: Constants.markMeterFloorDecibels - 1)) == 0)
        #expect(Mark.loudness(level: inputLevel(decibels: Constants.markMeterCeilingDecibels)) > 0.999)
        // Quiet talking must visibly move the bars.
        #expect(Mark.loudness(level: inputLevel(decibels: quietSpeechDecibels)) >= 1.0 / 3)
    }

    @Test("a resumed timeline advances by at most one capped frame")
    func frameIntervalCap() {
        #expect(Mark.frameInterval(from: nil, to: 10) == 0)
        #expect(Mark.frameInterval(from: 0, to: 10) == Constants.markMaxFrameInterval)
    }
}

@Suite("StoneMarkFrame")
struct StoneMarkFrameTests {
    let start = 1_000.0

    // The panel opens on the r and holds it, so the mark is recognized before it changes.
    @Test("listening holds the r, then the stones leave left to right")
    func holdThenStagger() {
        let held = StoneMarkFrame(seed: 1).running(.listening, from: start, for: Constants.markHoldSeconds - 0.01, fps: 120).frame
        #expect((0..<3).allSatisfy { held.progress(ofPiece: $0) == 0 })
        let leaving = StoneMarkFrame(seed: 1).running(.listening, from: start, for: Constants.markHoldSeconds + 0.03, fps: 120).frame
        #expect(leaving.progress(ofPiece: 0) > 0)
        #expect(leaving.progress(ofPiece: 2) == 0)
        let landed = StoneMarkFrame(seed: 1).running(.listening, from: start, for: 1.2, fps: 120).frame
        #expect((0..<3).allSatisfy { landed.progress(ofPiece: $0) > 0.99 })
    }

    // The exit retraces the entrance: the last stone to leave is the first back.
    @Test("on release the bars go back right to left, at once")
    func exitMirrors() {
        let (listening, end) = StoneMarkFrame(seed: 1).running(.listening, from: start, for: 1.2, fps: 120)
        let leaving = listening.running(.transcribing, from: end, for: 0.03, fps: 120).frame
        #expect(leaving.progress(ofPiece: 2) < 1)
        #expect(leaving.progress(ofPiece: 0) == 1 || leaving.progress(ofPiece: 0) > leaving.progress(ofPiece: 2))
        let back = listening.running(.transcribing, from: end, for: 1, fps: 120).frame
        #expect((0..<3).allSatisfy { back.progress(ofPiece: $0) < 0.01 })
    }

    // Measured frame by frame at 120 fps, as on the study page: with the bars' height tied to
    // the morph, no level lets a stone run into its neighbor going in or coming out (before the
    // rule, the foot and the hook overlapped for up to 67 ms above level 0.2).
    @Test("the stones never touch mid-morph, at any level, in either direction",
          arguments: [0.0, 0.3, 0.6, 1.0])
    func noOverlap(level: Double) {
        func closest(_ activity: MarkActivity, from frame: StoneMarkFrame, at time: Double) -> Double {
            var closest = Double.infinity
            _ = frame.running(activity, from: time, for: 1.2, fps: 120) { frame in
                // Only frames mid-morph can bring stones together; at rest and as bars they are apart.
                guard (0..<3).contains(where: { (0.0..<1.0).contains(frame.progress(ofPiece: $0)) && frame.progress(ofPiece: $0) > 0 }) else { return }
                let outlines = (0..<3).map { index in
                    StoneMark.blend(StoneMark.pieces[index],
                                    StoneMark.bar(index, level: StoneMarkPresentation.morphLevel(level, progress: frame.progress(ofPiece: index))),
                                    progress: frame.progress(ofPiece: index))
                }
                closest = min(closest, gap(outlines[0], outlines[1]), gap(outlines[1], outlines[2]))
            }
            return closest
        }
        let (listening, end) = StoneMarkFrame(seed: 1).running(.listening, from: start, for: 1.2, fps: 120)
        #expect(closest(.listening, from: StoneMarkFrame(seed: 1), at: start) > 3)
        #expect(closest(.transcribing, from: listening, at: end) > 3)
    }

    // Motion means sound: in a pause the bars sit at a stone's height and hold still, so a
    // dead or muted mic shows as bars that don't move while you talk.
    @Test("in silence the bars hold still at rest height")
    func silenceIsStill() {
        let (frame, end) = StoneMarkFrame(seed: 3).running(.listening, from: start, for: 1.5)
        let later = frame.running(.listening, from: end, for: 1).frame
        #expect((0..<3).allSatisfy { frame.bars[$0].level == 0 })
        #expect((0..<3).allSatisfy { frame.outline(ofPiece: $0) == later.outline(ofPiece: $0) })
    }

    @Test("the bars rise with the voice, louder higher, and settle when it stops")
    func barsFollowTheVoice() {
        func average(decibels: Double) -> Double {
            var total = 0.0, count = 0.0
            _ = StoneMarkFrame(seed: 5).running(.listening, from: start, for: 3, level: { _ in inputLevel(decibels: decibels) }) { frame in
                if frame.time! > start + 1.5 {
                    total += (0..<3).map { frame.displayedLevel(ofBar: $0) }.reduce(0, +) / 3
                    count += 1
                }
            }
            return total / count
        }
        #expect(average(decibels: quietSpeechDecibels) > 0.2)
        #expect(average(decibels: speechDecibels) > average(decibels: quietSpeechDecibels) + 0.2)
        let (speaking, end) = StoneMarkFrame(seed: 5).running(.listening, from: start, for: 2, level: { _ in inputLevel(decibels: speechDecibels) })
        let settled = speaking.running(.listening, from: end, for: 1.5).frame
        #expect((0..<3).allSatisfy { settled.displayedLevel(ofBar: $0) < 0.01 })
    }

    @Test("preparing holds the r still")
    func preparingIsStill() {
        var moved = false
        _ = StoneMarkFrame(seed: 1).running(.preparing, from: start, for: 2) { frame in
            moved = moved || (0..<3).contains { frame.progress(ofPiece: $0) != 0 } || frame.opacity != 1
        }
        #expect(!moved)
    }

    // Reduce Motion: no in-between shapes; the r and the bars swap at the bottom of a dip.
    @Test("under Reduce Motion the r and the bars swap behind a dip, after the hold")
    func reduceMotionSwaps() {
        var onlyEnds = true, lowest = 1.0, firstBars: Double?
        _ = StoneMarkFrame(seed: 1).running(.listening, from: start, for: 1.5, fps: 120, reduceMotion: true) { frame in
            for index in 0..<3 where ![0, 1].contains(frame.progress(ofPiece: index)) { onlyEnds = false }
            lowest = min(lowest, frame.opacity)
            if firstBars == nil, frame.progress(ofPiece: 0) == 1 { firstBars = frame.time }
        }
        #expect(onlyEnds)
        #expect(lowest < 0.1)
        #expect((firstBars ?? .infinity) - start >= Constants.markHoldSeconds)
    }

    @Test("the same seed gives the same frames")
    func deterministic() {
        let speaking: (Double) -> Double = { inputLevel(decibels: speechDecibels + 5 * sin($0 * 9)) }
        let a = StoneMarkFrame(seed: 9).running(.listening, from: start, for: 2, level: speaking).frame
        let b = StoneMarkFrame(seed: 9).running(.listening, from: start, for: 2, level: speaking).frame
        #expect(a == b)
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

    @Test("the fade is 0.22 s with a 6 pt rise")
    func fade() {
        #expect(Constants.hudFadeSeconds == 0.22)
        #expect(Constants.hudFadeRise == 6)
    }
}
